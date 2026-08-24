import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';
import 'dart:typed_data';
import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

class P2pApiResponse {
  final int status;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  P2pApiResponse({
    required this.status,
    required this.headers,
    required this.bodyBytes,
  });
}

enum P2pRtcChannel { api, file, upload, download, video }

class P2pApiStreamResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<Uint8List> stream;
  final void Function() cancel;

  P2pApiStreamResponse({
    required this.status,
    required this.headers,
    required this.stream,
    required this.cancel,
  });
}

class P2pRtcClient {
  /// 中继(relay)候选延迟发送时间，优先让 IPv4/IPv6 host、srflx 直连被测试，避免直连可用时仍走中继
  static const Duration _relayCandidateDelay = Duration(seconds: 4);

  /// 非正常结束流式响应体：用 [StreamController.addError] 结束，避免监听方把 [StreamController.close] 当成「整包读完」。
  static void _failP2pStreamBody(StreamController<Uint8List> c, Object error) {
    if (c.isClosed) return;
    try {
      c.addError(error, StackTrace.current);
    } catch (_) {}
    try {
      unawaited(c.close());
    } catch (_) {}
  }

  P2pRtcClient({
    required this.sessionId,
    required this.iceServers,
    this.iceTransportPolicy,
    required this.sendWsJson,
  });

  final String sessionId;
  final List<dynamic> iceServers;
  final String? iceTransportPolicy;
  final void Function(Map<String, dynamic>) sendWsJson;

  web.RTCPeerConnection? _pc;
  final Map<P2pRtcChannel, _RtcChannelState> _channels = {};
  Timer? _apiHeartbeatTimer;

  bool _isBulkChannel(P2pRtcChannel c) {
    return c == P2pRtcChannel.upload ||
        c == P2pRtcChannel.download ||
        c == P2pRtcChannel.video;
  }

  /// API / file 有在途请求时视为高优先级竞争，大流量通道应降低占用 SCTP。
  bool _hasHighPriorityContention() {
    final api = _channels[P2pRtcChannel.api];
    if (api != null &&
        (api.pending.isNotEmpty ||
            api.pendingChunks.isNotEmpty ||
            api.pendingStreams.isNotEmpty)) {
      return true;
    }
    final file = _channels[P2pRtcChannel.file];
    if (file != null &&
        (file.pending.isNotEmpty ||
            file.pendingChunks.isNotEmpty ||
            file.pendingStreams.isNotEmpty)) {
      return true;
    }
    return false;
  }

  /// 除 [except] 外是否还有其它大流量通道的流式请求（上传/下载/视频互让）。
  bool _hasOtherBulkActivity(P2pRtcChannel except) {
    for (final e in _channels.entries) {
      if (e.key == except) continue;
      if (!_isBulkChannel(e.key)) continue;
      if (e.value.pendingStreams.isNotEmpty) return true;
    }
    return false;
  }

  bool _hasVideoPriorityContentionFor(P2pRtcChannel channel) {
    if (channel != P2pRtcChannel.download && channel != P2pRtcChannel.upload) {
      return false;
    }
    final video = _channels[P2pRtcChannel.video];
    if (video == null) return false;
    return video.pendingStreams.isNotEmpty;
  }

  /// 非流式请求发送前的 bufferedAmount 上限（优先级: api/file > video > download/upload）。
  int _sendDrainLimitBytes(P2pRtcChannel channel) {
    if (channel == P2pRtcChannel.api) return 768 * 1024;
    if (channel == P2pRtcChannel.file) {
      return _hasHighPriorityContention() ? 640 * 1024 : 1024 * 1024;
    }

    final hp = _hasHighPriorityContention();
    final vp = _hasVideoPriorityContentionFor(channel);
    final otherBulk = _hasOtherBulkActivity(channel);

    if (channel == P2pRtcChannel.video) {
      if (hp) return 160 * 1024;
      if (otherBulk) return 384 * 1024;
      return 768 * 1024;
    }

    if (channel == P2pRtcChannel.download || channel == P2pRtcChannel.upload) {
      if (hp) return 48 * 1024;
      if (vp) return 64 * 1024;
      if (otherBulk) return 128 * 1024;
      return 256 * 1024;
    }

    return 256 * 1024;
  }

  /// 流式请求体发送时的 bufferedAmount 上限。
  int _streamSendDrainLimitBytes(P2pRtcChannel channel) {
    if (channel == P2pRtcChannel.api) return 768 * 1024;
    if (channel == P2pRtcChannel.file) {
      return _hasHighPriorityContention() ? 640 * 1024 : 1024 * 1024;
    }

    final hp = _hasHighPriorityContention();
    final vp = _hasVideoPriorityContentionFor(channel);
    final otherBulk = _hasOtherBulkActivity(channel);

    if (channel == P2pRtcChannel.video) {
      if (hp) return 192 * 1024;
      if (otherBulk) return 512 * 1024;
      return 1024 * 1024;
    }

    if (channel == P2pRtcChannel.download || channel == P2pRtcChannel.upload) {
      if (hp) return 96 * 1024;
      if (vp) return 128 * 1024;
      if (otherBulk) return 192 * 1024;
      return 512 * 1024;
    }

    return 384 * 1024;
  }

  int _bodyChunkSize(P2pRtcChannel channel) {
    if (channel == P2pRtcChannel.api) return 64 * 1024;
    if (channel == P2pRtcChannel.file) {
      return _hasHighPriorityContention() ? 16 * 1024 : 32 * 1024;
    }

    final hp = _hasHighPriorityContention();
    final vp = _hasVideoPriorityContentionFor(channel);

    if (channel == P2pRtcChannel.video) {
      if (hp) return 8 * 1024;
      return 16 * 1024;
    }

    if (channel == P2pRtcChannel.download || channel == P2pRtcChannel.upload) {
      if (hp) return 4 * 1024;
      if (vp) return 4 * 1024;
      if (_hasOtherBulkActivity(channel)) return 8 * 1024;
      return 16 * 1024;
    }

    return 16 * 1024;
  }

  /// 大流量通道发送 ACK 等控制帧前等待本 DC 出站缓冲回落。
  /// 否则在单 SCTP 关联上可能占满发送路径，导致 api/file 上的 `req:begin` 长期发不出去（对端日志只见 download:ack）。
  Future<void> _waitOutboundBeforeBulkControlSend(_RtcChannelState st) async {
    if (!_isBulkChannel(st.channel)) return;
    final dc = st.dc;
    final limit = _sendDrainLimitBytes(st.channel);
    final startedAt = DateTime.now();
    while (true) {
      if (dc.readyState != 'open') return;
      final amt = dc.bufferedAmount;
      if (amt <= limit) return;
      if (DateTime.now().difference(startedAt) > const Duration(seconds: 30)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// 在 api/file 发出控制帧前短暂等待大流量 DC 出站缓冲下降，给 SCTP 让出机会（中继下 download ACK 易占满关联）。
  Future<void> _yieldBulkBuffersBeforeHighPriorityControlSend() async {
    const maxWait = Duration(milliseconds: 800);
    const perDcLimit = 20 * 1024;
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      var congested = false;
      for (final e in _channels.entries) {
        if (!_isBulkChannel(e.key)) continue;
        final d = e.value.dc;
        if (d.readyState != 'open') continue;
        if (d.bufferedAmount > perDcLimit) {
          congested = true;
          break;
        }
      }
      if (!congested) return;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
  }

  Future<Uint8List> _readBlobBytes(web.Blob blob) async {
    final reader = web.FileReader();
    final completer = Completer<void>();

    reader.onload = (web.Event _) {
      completer.complete();
    }.toJS;

    reader.onerror = (web.Event _) {
      completer.completeError(
        reader.error ?? Exception('p2p_blob_read_failed'),
      );
    }.toJS;

    reader.readAsArrayBuffer(blob);
    await completer.future;

    final buffer = reader.result as JSArrayBuffer;
    return buffer.toDart.asUint8List();
  }

  Future<Uint8List?> _tryReadJsBlobBytes(dynamic raw) async {
    JSObject? o;
    try {
      o = raw as JSObject;
    } catch (_) {
      o = null;
    }
    if (o == null) return null;
    if (!o.hasProperty('arrayBuffer'.toJS).toDart) return null;
    try {
      final p = o.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS);
      final buf = await p.toDart;
      return buf.toDart.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _tryReadJsUint8ArrayBytes(dynamic raw) {
    JSUint8Array? arr;
    try {
      arr = raw as JSUint8Array;
    } catch (_) {
      arr = null;
    }
    if (arr == null) return null;
    try {
      return arr.toDart;
    } catch (_) {
      return null;
    }
  }

  static const int _p2pCtrlMagic0 = 0x4e;
  static const int _p2pCtrlMagic1 = 0x50;
  static const int _p2pCtrlMagic2 = 0x43;
  static const int _p2pCtrlVer1 = 0x01;

  static const int _p2pCtrlTypeReady = 0x01;
  static const int _p2pCtrlTypePing = 0x02;
  static const int _p2pCtrlTypePong = 0x03;
  static const int _p2pCtrlTypeReq = 0x10;
  static const int _p2pCtrlTypeReqBegin = 0x11;
  static const int _p2pCtrlTypeReqEnd = 0x12;
  static const int _p2pCtrlTypeReqCancel = 0x13;
  static const int _p2pCtrlTypeCancel = 0x14;
  static const int _p2pCtrlTypeResBegin = 0x20;
  static const int _p2pCtrlTypeResEnd = 0x21;
  static const int _p2pCtrlTypeFlow = 0x22;
  static const int _p2pCtrlTypeAck = 0x30;
  static const int _p2pCtrlTypeWsOpen = 0x40;
  static const int _p2pCtrlTypeWsSend = 0x41;
  static const int _p2pCtrlTypeWsClose = 0x42;
  static const int _p2pCtrlTypeWsOpenOk = 0x43;
  static const int _p2pCtrlTypeWsOpenError = 0x44;
  static const int _p2pCtrlTypeWsMessage = 0x45;
  static const int _p2pCtrlTypeWsError = 0x46;

  bool _isControlBinary(Uint8List bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == _p2pCtrlMagic0 &&
        bytes[1] == _p2pCtrlMagic1 &&
        bytes[2] == _p2pCtrlMagic2 &&
        bytes[3] == _p2pCtrlVer1;
  }

  void _writeVarint(BytesBuilder b, int value) {
    var v = value;
    if (v < 0) v = 0;
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v & 0xff);
  }

  int? _readVarint(Uint8List bytes, _IntRef offsetRef) {
    var shift = 0;
    var out = 0;
    while (true) {
      final off = offsetRef.value;
      if (off >= bytes.length) return null;
      final b = bytes[off];
      offsetRef.value = off + 1;
      out |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return out;
      shift += 7;
      if (shift > 63) return null;
    }
  }

  Uint8List? _readBytes(Uint8List bytes, _IntRef offsetRef) {
    final len = _readVarint(bytes, offsetRef);
    if (len == null || len < 0) return null;
    final off = offsetRef.value;
    final end = off + len;
    if (end > bytes.length) return null;
    offsetRef.value = end;
    if (len == 0) return Uint8List(0);
    return Uint8List.sublistView(bytes, off, end);
  }

  void _writeString(BytesBuilder b, String s) {
    if (s.isEmpty) {
      _writeVarint(b, 0);
      return;
    }
    final bytes = utf8.encode(s);
    _writeVarint(b, bytes.length);
    b.add(bytes);
  }

  String? _readString(Uint8List bytes, _IntRef offsetRef) {
    final raw = _readBytes(bytes, offsetRef);
    if (raw == null) return null;
    if (raw.isEmpty) return '';
    try {
      return utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  void _writeMapStrStr(BytesBuilder b, Map<String, String> m) {
    _writeVarint(b, m.length);
    m.forEach((k, v) {
      _writeString(b, k);
      _writeString(b, v);
    });
  }

  Map<String, String>? _readMapStrStr(Uint8List bytes, _IntRef offsetRef) {
    final n = _readVarint(bytes, offsetRef);
    if (n == null || n < 0) return null;
    final out = <String, String>{};
    for (var i = 0; i < n; i++) {
      final k = _readString(bytes, offsetRef);
      final v = _readString(bytes, offsetRef);
      if (k == null || v == null) return null;
      if (k.isNotEmpty) out[k] = v;
    }
    return out;
  }

  Uint8List? _tryEncodeControlBinary(String prefix, Map<String, dynamic> msg) {
    final typeRaw = msg['type']?.toString() ?? '';
    if (typeRaw.isEmpty) return null;
    final expectedPrefix = '$prefix:';
    if (!typeRaw.startsWith(expectedPrefix)) return null;
    final suffix = typeRaw.substring(expectedPrefix.length);

    int? mt;
    switch (suffix) {
      case 'ping':
        mt = _p2pCtrlTypePing;
        break;
      case 'pong':
        mt = _p2pCtrlTypePong;
        break;
      case 'req':
        mt = _p2pCtrlTypeReq;
        break;
      case 'req:begin':
        mt = _p2pCtrlTypeReqBegin;
        break;
      case 'req:end':
        mt = _p2pCtrlTypeReqEnd;
        break;
      case 'req:cancel':
        mt = _p2pCtrlTypeReqCancel;
        break;
      case 'cancel':
        mt = _p2pCtrlTypeCancel;
        break;
      case 'res:begin':
        mt = _p2pCtrlTypeResBegin;
        break;
      case 'res:end':
        mt = _p2pCtrlTypeResEnd;
        break;
      case 'flow':
        mt = _p2pCtrlTypeFlow;
        break;
      case 'ack':
        mt = _p2pCtrlTypeAck;
        break;
      case 'ws:open':
        mt = _p2pCtrlTypeWsOpen;
        break;
      case 'ws:send':
        mt = _p2pCtrlTypeWsSend;
        break;
      case 'ws:close':
        mt = _p2pCtrlTypeWsClose;
        break;
      default:
        return null;
    }

    final b = BytesBuilder(copy: false);
    b.add(const <int>[
      _p2pCtrlMagic0,
      _p2pCtrlMagic1,
      _p2pCtrlMagic2,
      _p2pCtrlVer1,
    ]);
    b.addByte(mt);

    if (mt == _p2pCtrlTypePing || mt == _p2pCtrlTypePong) {
      final ts = int.tryParse(msg['ts']?.toString() ?? '') ?? 0;
      _writeVarint(b, ts);
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeReqEnd ||
        mt == _p2pCtrlTypeReqCancel ||
        mt == _p2pCtrlTypeCancel ||
        mt == _p2pCtrlTypeResEnd) {
      _writeString(b, msg['id']?.toString() ?? '');
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeAck) {
      _writeString(b, msg['id']?.toString() ?? '');
      final delta = int.tryParse(msg['delta']?.toString() ?? '') ?? 0;
      _writeVarint(b, delta);
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeFlow) {
      _writeString(b, msg['id']?.toString() ?? '');
      _writeString(b, msg['action']?.toString() ?? '');
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeReq || mt == _p2pCtrlTypeReqBegin) {
      final headers = <String, String>{};
      final headersRaw = msg['headers'];
      if (headersRaw is Map) {
        headersRaw.forEach((k, v) {
          final key = (k ?? '').toString();
          if (key.isEmpty) return;
          headers[key] = (v ?? '').toString();
        });
      }
      _writeString(b, msg['id']?.toString() ?? '');
      _writeString(b, msg['method']?.toString() ?? '');
      _writeString(b, msg['path']?.toString() ?? '');
      _writeMapStrStr(b, headers);
      if (mt == _p2pCtrlTypeReqBegin) {
        final len = int.tryParse(msg['length']?.toString() ?? '') ?? 0;
        _writeVarint(b, len);
      }
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeResBegin) {
      final headers = <String, String>{};
      final headersRaw = msg['headers'];
      if (headersRaw is Map) {
        headersRaw.forEach((k, v) {
          final key = (k ?? '').toString();
          if (key.isEmpty) return;
          headers[key] = (v ?? '').toString();
        });
      }
      _writeString(b, msg['id']?.toString() ?? '');
      final status = int.tryParse(msg['status']?.toString() ?? '') ?? 0;
      _writeVarint(b, status);
      _writeMapStrStr(b, headers);
      final len = int.tryParse(msg['length']?.toString() ?? '') ?? 0;
      _writeVarint(b, len);
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeWsOpen) {
      final headers = <String, String>{};
      final headersRaw = msg['headers'];
      if (headersRaw is Map) {
        headersRaw.forEach((k, v) {
          final key = (k ?? '').toString();
          if (key.isEmpty) return;
          headers[key] = (v ?? '').toString();
        });
      }
      _writeString(b, msg['id']?.toString() ?? '');
      _writeString(b, msg['path']?.toString() ?? '');
      _writeMapStrStr(b, headers);
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeWsSend) {
      _writeString(b, msg['id']?.toString() ?? '');
      _writeString(b, msg['data']?.toString() ?? '');
      return b.takeBytes();
    }

    if (mt == _p2pCtrlTypeWsClose) {
      _writeString(b, msg['id']?.toString() ?? '');
      final code = int.tryParse(msg['code']?.toString() ?? '') ?? 0;
      _writeVarint(b, code);
      _writeString(b, msg['reason']?.toString() ?? '');
      return b.takeBytes();
    }

    return null;
  }

  Map<String, dynamic>? _tryDecodeControlBinary(
    String prefix,
    Uint8List bytes,
  ) {
    if (!_isControlBinary(bytes)) return null;
    final mt = bytes[4];
    final off = _IntRef(5);
    final typePrefix = '$prefix:';

    if (mt == _p2pCtrlTypePing || mt == _p2pCtrlTypePong) {
      final ts = _readVarint(bytes, off);
      if (ts == null) return null;
      return <String, dynamic>{
        'type': '$typePrefix${mt == _p2pCtrlTypePing ? 'ping' : 'pong'}',
        'ts': ts,
      };
    }

    if (mt == _p2pCtrlTypeReqEnd ||
        mt == _p2pCtrlTypeReqCancel ||
        mt == _p2pCtrlTypeCancel ||
        mt == _p2pCtrlTypeResEnd) {
      final id = _readString(bytes, off);
      if (id == null) return null;
      String suffix = '';
      if (mt == _p2pCtrlTypeReqEnd) suffix = 'req:end';
      if (mt == _p2pCtrlTypeReqCancel) suffix = 'req:cancel';
      if (mt == _p2pCtrlTypeCancel) suffix = 'cancel';
      if (mt == _p2pCtrlTypeResEnd) suffix = 'res:end';
      return <String, dynamic>{'type': '$typePrefix$suffix', 'id': id};
    }

    if (mt == _p2pCtrlTypeAck) {
      final id = _readString(bytes, off);
      final delta = _readVarint(bytes, off);
      if (id == null || delta == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ack',
        'id': id,
        'delta': delta,
      };
    }

    if (mt == _p2pCtrlTypeFlow) {
      final id = _readString(bytes, off);
      final action = _readString(bytes, off);
      if (id == null || action == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}flow',
        'id': id,
        'action': action,
      };
    }

    if (mt == _p2pCtrlTypeReq || mt == _p2pCtrlTypeReqBegin) {
      final id = _readString(bytes, off);
      final method = _readString(bytes, off);
      final path = _readString(bytes, off);
      final headers = _readMapStrStr(bytes, off);
      if (id == null || method == null || path == null || headers == null) {
        return null;
      }
      if (mt == _p2pCtrlTypeReqBegin) {
        final len = _readVarint(bytes, off);
        if (len == null) return null;
        return <String, dynamic>{
          'type': '${typePrefix}req:begin',
          'id': id,
          'method': method,
          'path': path,
          'headers': headers,
          'length': len,
        };
      }
      return <String, dynamic>{
        'type': '${typePrefix}req',
        'id': id,
        'method': method,
        'path': path,
        'headers': headers,
      };
    }

    if (mt == _p2pCtrlTypeResBegin) {
      final id = _readString(bytes, off);
      final status = _readVarint(bytes, off);
      final headers = _readMapStrStr(bytes, off);
      final len = _readVarint(bytes, off);
      if (id == null || status == null || headers == null || len == null) {
        return null;
      }
      return <String, dynamic>{
        'type': '${typePrefix}res:begin',
        'id': id,
        'status': status,
        'headers': headers,
        'length': len,
      };
    }

    if (mt == _p2pCtrlTypeWsOpen) {
      final id = _readString(bytes, off);
      final path = _readString(bytes, off);
      final headers = _readMapStrStr(bytes, off);
      if (id == null || path == null || headers == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:open',
        'id': id,
        'path': path,
        'headers': headers,
      };
    }

    if (mt == _p2pCtrlTypeWsSend) {
      final id = _readString(bytes, off);
      final data = _readString(bytes, off);
      if (id == null || data == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:send',
        'id': id,
        'data': data,
      };
    }

    if (mt == _p2pCtrlTypeWsClose) {
      final id = _readString(bytes, off);
      final code = _readVarint(bytes, off);
      final reason = _readString(bytes, off);
      if (id == null || code == null || reason == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:close',
        'id': id,
        if (code > 0) 'code': code,
        if (reason.isNotEmpty) 'reason': reason,
      };
    }

    if (mt == _p2pCtrlTypeWsOpenOk) {
      final id = _readString(bytes, off);
      if (id == null) return null;
      return <String, dynamic>{'type': '${typePrefix}ws:open:ok', 'id': id};
    }

    if (mt == _p2pCtrlTypeWsOpenError) {
      final id = _readString(bytes, off);
      final error = _readString(bytes, off);
      if (id == null || error == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:open:error',
        'id': id,
        'error': error,
      };
    }

    if (mt == _p2pCtrlTypeWsMessage) {
      final id = _readString(bytes, off);
      final data = _readString(bytes, off);
      if (id == null || data == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:message',
        'id': id,
        'data': data,
      };
    }

    if (mt == _p2pCtrlTypeWsError) {
      final id = _readString(bytes, off);
      final error = _readString(bytes, off);
      if (id == null || error == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ws:error',
        'id': id,
        'error': error,
      };
    }

    if (mt == _p2pCtrlTypeReady) {
      final cbv2 = _readVarint(bytes, off);
      if (cbv2 == null) return null;
      return <String, dynamic>{
        'type': '${typePrefix}ready',
        'features': <String, dynamic>{
          'chunkBinaryV2': cbv2 != 0,
        },
      };
    }

    return null;
  }

  void _sendControlMessage(_RtcChannelState st, Map<String, dynamic> msg) {
    final dc = st.dc;
    if (dc.readyState != 'open') throw StateError('p2p_dc_not_open');
    final bin = _tryEncodeControlBinary(st.prefix, msg);
    if (bin == null) {
      throw Exception('p2p_ctrl_unsupported_type');
    }
    st.txPackets += 1;
    st.txBytes += bin.length;
    st.lastTxAtMs = DateTime.now().millisecondsSinceEpoch;
    dc.send(bin.toJS);
  }

  Future<void> _handleDcMessage(_RtcChannelState st, dynamic raw) async {
    if (raw == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    st.lastRxAtMs = nowMs;

    Uint8List? bytes;
    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is ByteBuffer) {
      bytes = raw.asUint8List();
    } else {
      JSArrayBuffer? ab;
      try {
        ab = raw as JSArrayBuffer;
      } catch (_) {
        ab = null;
      }
      if (ab != null) {
        bytes = ab.toDart.asUint8List();
      } else {
        bytes = _tryReadJsUint8ArrayBytes(raw);
      }
    }

    bytes ??= await _tryReadJsBlobBytes(raw);

    if (bytes == null) {
      web.Blob? blob;
      try {
        blob = raw as web.Blob;
      } catch (_) {
        blob = null;
      }
      if (blob != null) {
        try {
          bytes = await _readBlobBytes(blob);
        } catch (_) {
          bytes = null;
        }
      }
    }

    if (bytes == null && raw is String) {
      final s = raw;
      if (s.isNotEmpty) {
        try {
          bytes = latin1.encode(s);
        } catch (_) {
          bytes = null;
        }
      }
    }

    if (bytes != null &&
        bytes.isNotEmpty &&
        bytes[0] == 0x01) {
      st.rxPackets += 1;
      st.rxBytes += bytes.length;
      await _handleBinaryChunk(st, bytes);
      return;
    }

    if (bytes != null) {
      final decoded = _tryDecodeControlBinary(st.prefix, bytes);
      if (decoded != null) {
        st.rxPackets += 1;
        st.rxBytes += bytes.length;
        _onChannelMessage(st, decoded);
        return;
      }
    }
  }

  String _prefixForChannel(P2pRtcChannel c) {
    if (c == P2pRtcChannel.api) return 'api';
    if (c == P2pRtcChannel.file) return 'file';
    if (c == P2pRtcChannel.upload) return 'upload';
    if (c == P2pRtcChannel.download) return 'download';
    return 'video';
  }

  _RtcChannelState _requireChannel(P2pRtcChannel c) {
    final st = _channels[c];
    if (st == null) throw Exception('p2p_not_connected');
    return st;
  }

  Future<void> start({List<P2pRtcChannel>? channels}) async {
    final sid = sessionId.trim();
    if (sid.isEmpty) {
      throw Exception('p2p_session_invalid');
    }

    final jsIceServers = <web.RTCIceServer>[];
    for (final s in iceServers) {
      if (s is! Map) continue;
      final rawUrls = s['urls'];
      JSAny? urls;
      if (rawUrls is String && rawUrls.trim().isNotEmpty) {
        urls = rawUrls.trim().toJS;
      } else if (rawUrls is List) {
        final list = rawUrls
            .map((e) => (e ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          urls = list.map((e) => e.toJS).toList().toJS;
        }
      }
      if (urls == null) continue;
      final username = (s['username'] ?? '').toString();
      final credential = (s['credential'] ?? '').toString();
      jsIceServers.add(
        web.RTCIceServer(
          urls: urls,
          username: username,
          credential: credential,
        ),
      );
    }
    final policy = (iceTransportPolicy ?? '').trim().toLowerCase();
    final skipRelayCandidateDelay = policy == 'relay';
    final config = policy == 'relay'
        ? web.RTCConfiguration(
            iceServers: jsIceServers.toJS,
            iceTransportPolicy: 'relay',
          )
        : web.RTCConfiguration(iceServers: jsIceServers.toJS);
    final pc = web.RTCPeerConnection(config);
    _pc = pc;

    pc.onicecandidate = ((web.Event ev) {
      final e = ev as web.RTCPeerConnectionIceEvent;
      final c = e.candidate;
      if (c == null) return;
      final candidateStr = c.candidate;
      final parts = candidateStr.split(' ');
      final typIdx = parts.indexOf('typ');
      final typ = typIdx >= 0 && typIdx + 1 < parts.length
          ? parts[typIdx + 1]
          : '';

      final payload = <String, dynamic>{
        'type': 'webrtc:candidate',
        'sessionId': sid,
        'candidate': <String, dynamic>{
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      };

      if (typ == 'relay' && !skipRelayCandidateDelay) {
        // 延迟发送中继候选，让直连（IPv4/IPv6 host、srflx）优先被测试和 nominated
        // 若延迟内已直连成功，则丢弃该中继候选，避免被随机选中
        Timer(_relayCandidateDelay, () {
          if (_pc == null) return;
          if (_pc!.connectionState == 'connected') return;
          sendWsJson(payload);
        });
      } else {
        sendWsJson(payload);
      }
    }).toJS;

    pc.onconnectionstatechange = ((web.Event _) {
      final cs = pc.connectionState;
      // `disconnected` 在 ICE 重启/路径切换时常为瞬时状态，不应立即 teardown，否则下载流会被 close 误判为成功结束。
      if (cs == 'failed' || cs == 'closed') {
        unawaited(close());
      }
    }).toJS;

    pc.oniceconnectionstatechange = ((web.Event _) {
      final cs = pc.iceConnectionState;
      if (cs == 'failed' || cs == 'closed') {
        unawaited(close());
      }
    }).toJS;

    void attachChannel(P2pRtcChannel c) {
      final prefix = _prefixForChannel(c);
      final ready = Completer<void>();
      final dc = pc.createDataChannel(prefix);
      dc.binaryType = 'arraybuffer';
      final st = _RtcChannelState(
        channel: c,
        prefix: prefix,
        dc: dc,
        ready: ready,
      );
      _channels[c] = st;

      dc.onopen = ((web.Event _) {
        print('[P2pRtc] dc open $prefix');
      }).toJS;

      dc.onclose = ((web.Event _) {
        print('[P2pRtc] dc close $prefix');
        if (!ready.isCompleted) {
          ready.completeError(Exception('p2p_dc_closed'));
        }
        final pending = List<Completer<P2pApiResponse>>.from(st.pending.values);
        for (final c in pending) {
          if (!c.isCompleted) c.completeError(Exception('p2p_dc_closed'));
        }
        st.pending.clear();
        st.pendingChunks.clear();
        final pendingStreams = List<_PendingStream>.from(
          st.pendingStreams.values,
        );
        for (final pst in pendingStreams) {
          if (!pst.start.isCompleted) {
            pst.start.completeError(Exception('p2p_dc_closed'));
          }
          _failP2pStreamBody(pst.controller, Exception('p2p_dc_closed'));
        }
        st.pendingStreams.clear();
        final tunnels = List<_P2pRtcWebSocketChannel>.from(st.wsTunnels.values);
        for (final ch in tunnels) {
          ch._handleRemoteClose(1001, 'p2p_dc_closed');
        }
        st.wsTunnels.clear();
      }).toJS;

      dc.onerror = ((web.Event _) {
        if (!ready.isCompleted) {
          ready.completeError(Exception('p2p_dc_error'));
        }
      }).toJS;

      dc.onmessage = ((web.Event ev) {
        final me = ev as web.MessageEvent;
        final raw = me.data as dynamic;
        st.rxQueue = st.rxQueue
            .catchError((_) {})
            .then((_) => _handleDcMessage(st, raw));
      }).toJS;
    }

    final wanted = (channels == null || channels.isEmpty)
        ? const <P2pRtcChannel>[
            P2pRtcChannel.api,
            P2pRtcChannel.file,
            P2pRtcChannel.upload,
            P2pRtcChannel.download,
            P2pRtcChannel.video,
          ]
        : channels;
    for (final c in wanted) {
      attachChannel(c);
    }

    final offer = await pc.createOffer().toDart;
    if (offer == null) {
      throw Exception('p2p_offer_failed');
    }
    final offerType = offer.type;
    final offerSdp = offer.sdp;
    final offerMap = <String, dynamic>{'type': offerType, 'sdp': offerSdp};
    await pc
        .setLocalDescription(
          web.RTCLocalSessionDescriptionInit(type: offerType, sdp: offerSdp),
        )
        .toDart;
    sendWsJson({'type': 'webrtc:offer', 'sessionId': sid, 'offer': offerMap});

    await Future.wait(
      _channels.values.map((e) => e.ready.future),
    ).timeout(const Duration(seconds: 20));
  }

  Future<Map<String, String>> getTransportStats() async {
    // Web implementation TODO
    return {};
  }

  /// 主 API 数据通道是否处于 open 状态。
  /// 用于区分"主 P2P 真的断连"和"专用 link（视频/上传/下载）本地故障"，
  /// 避免后者错误地触发全局 _forceReconnectP2p。
  bool get isApiChannelOpen {
    final ch = _channels[P2pRtcChannel.api];
    if (ch == null) return false;
    return ch.dc.readyState == 'open';
  }

  bool get isDownloadChannelOpen {
    final ch = _channels[P2pRtcChannel.download];
    if (ch == null) return false;
    return ch.dc.readyState == 'open';
  }

  bool get isUploadChannelOpen {
    final ch = _channels[P2pRtcChannel.upload];
    if (ch == null) return false;
    return ch.dc.readyState == 'open';
  }

  bool get isVideoChannelOpen {
    final ch = _channels[P2pRtcChannel.video];
    if (ch == null) return false;
    return ch.dc.readyState == 'open';
  }

  /// 是否有正在进行中的请求（任意通道）。
  /// 用于 relay→direct 升级前的保护：有 in-flight 请求时不切换，避免中断传输。
  bool get hasPendingRequests {
    for (final st in _channels.values) {
      if (st.pending.isNotEmpty ||
          st.pendingChunks.isNotEmpty ||
          st.pendingStreams.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// 流式 / 分块 响应共用：ACK 聚合阈值与定时 flush 间隔。
  (int immediateThreshold, Duration delay) _ackFlushTiming(_RtcChannelState st) {
    final hp = _hasHighPriorityContention();
    switch (st.channel) {
      case P2pRtcChannel.api:
        return (96 * 1024, const Duration(milliseconds: 15));
      case P2pRtcChannel.file:
        return (
          hp ? 80 * 1024 : 192 * 1024,
          hp
              ? const Duration(milliseconds: 18)
              : const Duration(milliseconds: 45),
        );
      case P2pRtcChannel.video:
        return (
          hp ? 24 * 1024 : 64 * 1024,
          hp
              ? const Duration(milliseconds: 12)
              : const Duration(milliseconds: 24),
        );
      case P2pRtcChannel.download:
        final vp = _hasVideoPriorityContentionFor(st.channel);
        if (hp) {
          return (96 * 1024, const Duration(milliseconds: 30));
        }
        if (vp) {
          return (128 * 1024, const Duration(milliseconds: 36));
        }
        return (256 * 1024, const Duration(milliseconds: 48));
      case P2pRtcChannel.upload:
        final vp = _hasVideoPriorityContentionFor(st.channel);
        if (hp) {
          return (8 * 1024, const Duration(milliseconds: 8));
        }
        if (vp) {
          return (12 * 1024, const Duration(milliseconds: 10));
        }
        return (24 * 1024, const Duration(milliseconds: 18));
    }
  }

  int _downloadAckLastMs(
    _RtcChannelState st,
    String id, {
    _PendingStream? clockStream,
    _PendingChunk? clockChunk,
  }) {
    if (clockStream != null) return clockStream.lastAckSentMs;
    if (clockChunk != null) return clockChunk.lastAckSentMs;
    return st.pendingStreams[id]?.lastAckSentMs ??
        st.pendingChunks[id]?.lastAckSentMs ??
        0;
  }

  void _downloadAckMarkSent(
    _RtcChannelState st,
    String id, {
    _PendingStream? clockStream,
    _PendingChunk? clockChunk,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (clockStream != null) {
      clockStream.lastAckSentMs = now;
      return;
    }
    if (clockChunk != null) {
      clockChunk.lastAckSentMs = now;
      return;
    }
    final ps = st.pendingStreams[id];
    if (ps != null) {
      ps.lastAckSentMs = now;
      return;
    }
    final pc = st.pendingChunks[id];
    if (pc != null) {
      pc.lastAckSentMs = now;
    }
  }

  Future<void> _sendStreamAckDelta(
    _RtcChannelState st,
    String id,
    int delta, {
    _PendingStream? downloadClockStream,
    _PendingChunk? downloadClockChunk,
  }) async {
    if (delta <= 0) return;
    final dc = st.dc;
    if (dc.readyState != 'open') return;
    try {
      if (st.channel == P2pRtcChannel.download) {
        final minGapMs = _hasHighPriorityContention() ? 45 : 85;
        final now = DateTime.now().millisecondsSinceEpoch;
        final last = _downloadAckLastMs(
          st,
          id,
          clockStream: downloadClockStream,
          clockChunk: downloadClockChunk,
        );
        if (last > 0 && now - last < minGapMs) {
          await Future<void>.delayed(
            Duration(milliseconds: minGapMs - (now - last)),
          );
        }
      }
      await _waitOutboundBeforeBulkControlSend(st);
      _sendControlMessage(st, {
        'type': '${st.prefix}:ack',
        'id': id,
        'delta': delta,
      });
      if (st.channel == P2pRtcChannel.download) {
        _downloadAckMarkSent(
          st,
          id,
          clockStream: downloadClockStream,
          clockChunk: downloadClockChunk,
        );
      }
    } catch (_) {}
  }

  Future<void> _flushStreamAck(
    _RtcChannelState st,
    String id,
    _PendingStream sst, {
    bool detached = false,
  }) async {
    final delta = sst.ackPendingBytes;
    if (delta <= 0) return;
    sst.ackPendingBytes = 0;
    await _sendStreamAckDelta(
      st,
      id,
      delta,
      downloadClockStream:
          detached && st.channel == P2pRtcChannel.download ? sst : null,
    );
  }

  Future<void> _flushChunkAck(
    _RtcChannelState st,
    String id,
    _PendingChunk stc, {
    bool detached = false,
  }) async {
    final delta = stc.chunkAckPendingBytes;
    if (delta <= 0) return;
    stc.chunkAckPendingBytes = 0;
    await _sendStreamAckDelta(
      st,
      id,
      delta,
      downloadClockChunk:
          detached && st.channel == P2pRtcChannel.download ? stc : null,
    );
  }

  void _cancelPendingStream(_RtcChannelState st, String id, String error) {
    final pst = st.pendingStreams.remove(id);
    if (pst == null) return;
    final dc = st.dc;
    try {
      if (dc.readyState == 'open') {
        _sendControlMessage(st, {'type': '${st.prefix}:cancel', 'id': id});
      }
    } catch (_) {}
    if (!pst.start.isCompleted) {
      pst.start.completeError(Exception(error));
    }
    _failP2pStreamBody(pst.controller, Exception(error));
  }

  void _scheduleStreamAck(_RtcChannelState st, String id, int delta) {
    if (delta <= 0) return;
    final sst = st.pendingStreams[id];
    if (sst == null) return;
    sst.ackPendingBytes += delta;
    _ensureStreamAckFlushScheduled(st, id);
  }

  /// 须在异步 flush 结束后再清 ackScheduled，否则会叠加多个 Timer，导致 download:ack 风暴。
  void _ensureStreamAckFlushScheduled(_RtcChannelState st, String id) {
    final sst = st.pendingStreams[id];
    if (sst == null) return;
    if (sst.ackScheduled) return;
    sst.ackScheduled = true;

    final (immediateThreshold, delay) = _ackFlushTiming(st);
    final immediate = st.channel != P2pRtcChannel.download &&
        sst.ackPendingBytes >= immediateThreshold;
    void kick() {
      unawaited(() async {
        final cur = st.pendingStreams[id];
        if (cur == null) return;
        try {
          await _flushStreamAck(st, id, cur);
        } finally {
          cur.ackScheduled = false;
          if (cur.ackPendingBytes > 0 && st.pendingStreams.containsKey(id)) {
            _ensureStreamAckFlushScheduled(st, id);
          }
        }
      }());
    }

    if (immediate) {
      scheduleMicrotask(kick);
    } else {
      Timer(delay, kick);
    }
  }

  /// 非流式分块响应（pendingChunks）的 ACK 与流式共用节奏，避免 upload/video/file 等通道每包一 ACK。
  void _scheduleChunkAck(_RtcChannelState st, String id, int delta) {
    if (delta <= 0) return;
    final stc = st.pendingChunks[id];
    if (stc == null) return;
    stc.chunkAckPendingBytes += delta;
    _ensureChunkAckFlushScheduled(st, id);
  }

  void _ensureChunkAckFlushScheduled(_RtcChannelState st, String id) {
    final stc = st.pendingChunks[id];
    if (stc == null) return;
    if (stc.chunkAckScheduled) return;
    stc.chunkAckScheduled = true;

    final (immediateThreshold, delay) = _ackFlushTiming(st);
    final immediate = st.channel != P2pRtcChannel.download &&
        stc.chunkAckPendingBytes >= immediateThreshold;
    void kick() {
      unawaited(() async {
        final cur = st.pendingChunks[id];
        if (cur == null) return;
        try {
          await _flushChunkAck(st, id, cur);
        } finally {
          cur.chunkAckScheduled = false;
          if (cur.chunkAckPendingBytes > 0 && st.pendingChunks.containsKey(id)) {
            _ensureChunkAckFlushScheduled(st, id);
          }
        }
      }());
    }

    if (immediate) {
      scheduleMicrotask(kick);
    } else {
      Timer(delay, kick);
    }
  }

  Future<void> _handleBinaryChunk(_RtcChannelState st, Uint8List bytes) async {
    if (bytes.isEmpty || bytes[0] != 0x01) return;
    if (bytes.length < 2) return;
    var offset = 1;
    final idLen = bytes[offset];
    offset++;
    if (offset + idLen > bytes.length) return;

    String id;
    try {
      final cachedBytes = st.cachedChunkIdBytes;
      if (cachedBytes != null && cachedBytes.length == idLen) {
        var same = true;
        for (var i = 0; i < idLen; i++) {
          if (cachedBytes[i] != bytes[offset + i]) {
            same = false;
            break;
          }
        }
        if (same) {
          id = st.cachedChunkId ?? '';
        } else {
          id = latin1.decode(
            Uint8List.sublistView(bytes, offset, offset + idLen),
          );
          st.cachedChunkId = id;
          st.cachedChunkIdBytes = Uint8List.fromList(
            Uint8List.sublistView(bytes, offset, offset + idLen),
          );
        }
      } else {
        id = latin1.decode(
          Uint8List.sublistView(bytes, offset, offset + idLen),
        );
        st.cachedChunkId = id;
        st.cachedChunkIdBytes = Uint8List.fromList(
          Uint8List.sublistView(bytes, offset, offset + idLen),
        );
      }
    } catch (_) {
      return;
    }
    if (id.isEmpty) return;
    offset += idLen;
    final payload = Uint8List.sublistView(bytes, offset);

    final sst = st.pendingStreams[id];
    if (sst != null) {
      final n = payload.length;
      if (n > 0) {
        try {
          sst.controller.add(payload);
        } catch (_) {
          _cancelPendingStream(st, id, 'p2p_stream_controller_error');
          return;
        }
        _scheduleStreamAck(st, id, n);
      }
      return;
    }

    final stc = st.pendingChunks[id];
    if (stc != null) {
      stc.builder.add(payload);
      _scheduleChunkAck(st, id, payload.length);
    }
  }

  void _onChannelMessage(_RtcChannelState st, Map<String, dynamic> m) {
    final prefix = st.prefix;
    final type = m['type']?.toString() ?? '';
    if (type == '$prefix:ready') {
      final featuresRaw = m['features'];
      if (featuresRaw is Map) {
        st.supportsChunkBinaryV2 = featuresRaw['chunkBinaryV2'] == true;
      }
      if (!st.ready.isCompleted) st.ready.complete();
      st.lastRxAtMs = DateTime.now().millisecondsSinceEpoch;
      _apiHeartbeatTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final channels = List<_RtcChannelState>.from(_channels.values);
        var shouldClose = false;
        for (final ch in channels) {
          if (ch.ready.isCompleted &&
              (ch.pending.isNotEmpty ||
                  ch.pendingChunks.isNotEmpty ||
                  ch.pendingStreams.isNotEmpty ||
                  ch.wsTunnels.isNotEmpty) &&
              ch.lastRxAtMs > 0 &&
              (nowMs - ch.lastRxAtMs) > 25000) {
            shouldClose = true;
            break;
          }
          final dc = ch.dc;
          if (dc.readyState != 'open') continue;
          try {
            _sendControlMessage(ch, {'type': '${ch.prefix}:ping', 'ts': nowMs});
          } catch (_) {}
        }
        if (shouldClose) {
          unawaited(close());
        }
      });
      return;
    }
    if (type == '$prefix:ping') {
      final dc = st.dc;
      if (dc.readyState != 'open') return;
      try {
        _sendControlMessage(st, {
          'type': '$prefix:pong',
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
      return;
    }
    if (type == '$prefix:pong') {
      return;
    }
    if (type == '$prefix:ws:open:ok') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final ch = st.wsTunnels[id];
      ch?._handleOpenOk();
      return;
    }
    if (type == '$prefix:ws:open:error') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final err = m['error']?.toString() ?? 'open_failed';
      final ch = st.wsTunnels.remove(id);
      ch?._handleOpenError(err);
      return;
    }
    if (type == '$prefix:ws:message') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final data = m['data']?.toString() ?? '';
      final ch = st.wsTunnels[id];
      ch?._handleMessage(data);
      return;
    }
    if (type == '$prefix:ws:error') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final err = m['error']?.toString() ?? 'ws_error';
      final ch = st.wsTunnels.remove(id);
      ch?._handleRemoteError(err);
      return;
    }
    if (type == '$prefix:ws:close') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final code = int.tryParse(m['code']?.toString() ?? '');
      final reason = m['reason']?.toString();
      final ch = st.wsTunnels.remove(id);
      ch?._handleRemoteClose(code, reason);
      return;
    }
    if (type == '$prefix:res:begin') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final sst = st.pendingStreams[id];
      if (sst != null) {
        final status = int.tryParse(m['status']?.toString() ?? '') ?? 500;
        final headers = <String, String>{};
        final headersRaw = m['headers'];
        if (headersRaw is Map) {
          headersRaw.forEach((k, v) {
            final key = (k ?? '').toString().trim();
            if (key.isEmpty) return;
            headers[key.toLowerCase()] = (v ?? '').toString();
          });
        }
        if (!sst.start.isCompleted) {
          sst.start.complete(_StreamStart(status: status, headers: headers));
        }
        return;
      }
      final c = st.pending[id];
      if (c == null || c.isCompleted) {
        return;
      }
      final status = int.tryParse(m['status']?.toString() ?? '') ?? 500;
      final headers = <String, String>{};
      final headersRaw = m['headers'];
      if (headersRaw is Map) {
        headersRaw.forEach((k, v) {
          final key = (k ?? '').toString().trim();
          if (key.isEmpty) return;
          headers[key.toLowerCase()] = (v ?? '').toString();
        });
      }
      final length = int.tryParse(m['length']?.toString() ?? '') ?? 0;
      st.pendingChunks[id] = _PendingChunk(
        completer: c,
        status: status,
        headers: headers,
        builder: BytesBuilder(copy: false),
        length: length,
      );
      return;
    }
    if (type == '$prefix:res:end') {
      final id = m['id']?.toString() ?? '';
      if (id.isEmpty) return;
      final sst = st.pendingStreams.remove(id);
      if (sst != null) {
        unawaited(() async {
          try {
            await _flushStreamAck(st, id, sst, detached: true);
          } catch (_) {}
          if (!sst.start.isCompleted) {
            sst.start.complete(
              _StreamStart(status: 200, headers: const <String, String>{}),
            );
          }
          try {
            await sst.controller.close();
          } catch (_) {}
        }());
        return;
      }
      final stc = st.pendingChunks.remove(id);
      if (stc == null) return;
      st.pending.remove(id);
      if (stc.completer.isCompleted) return;
      final encoded = stc.builder.takeBytes();
      unawaited(() async {
        try {
          await _flushChunkAck(st, id, stc, detached: true);
        } catch (_) {}
        stc.chunkAckScheduled = false;
        if (!stc.completer.isCompleted) {
          stc.completer.complete(
            P2pApiResponse(
              status: stc.status,
              headers: stc.headers,
              bodyBytes: encoded,
            ),
          );
        }
      }());
    }
  }

  WebSocketChannel openWebSocketChannel({
    required P2pRtcChannel channel,
    required String path,
    Map<String, String> headers = const <String, String>{},
  }) {
    final st = _requireChannel(channel);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';

    final outgoingHeaders = <String, String>{};
    headers.forEach((k, v) {
      final key = k.trim();
      if (key.isEmpty) return;
      outgoingHeaders[key] = v;
    });

    late _P2pRtcWebSocketChannel ws;
    ws = _P2pRtcWebSocketChannel(
      id: id,
      prefix: st.prefix,
      sendJson: (payload) {
        _sendControlMessage(st, payload);
      },
      onClose: () {
        st.wsTunnels.remove(id);
      },
    );
    st.wsTunnels[id] = ws;

    () async {
      try {
        await st.ready.future.timeout(const Duration(seconds: 15));
        if (st.dc.readyState != 'open') {
          throw Exception('p2p_dc_not_open');
        }
        final safePath = path.trim();
        if (safePath.isEmpty || !safePath.startsWith('/')) {
          st.wsTunnels.remove(id);
          ws._handleOpenError('invalid_path');
          return;
        }
        ws._sendOpen(safePath, outgoingHeaders);
      } catch (e) {
        st.wsTunnels.remove(id);
        ws._handleOpenError(e.toString());
      }
    }();

    return ws;
  }

  void handleWsMessage(Map<String, dynamic> msg) {
    final pc = _pc;
    if (pc == null) return;

    final type = msg['type']?.toString() ?? '';
    final sid = msg['sessionId']?.toString() ?? '';
    if (sid.isNotEmpty && sid != sessionId) return;

    if (type == 'webrtc:answer' && msg['answer'] != null) {
      final a = msg['answer'];
      if (a is Map) {
        final type = (a['type'] ?? '').toString();
        final sdp = (a['sdp'] ?? '').toString();
        if (type.isNotEmpty && sdp.isNotEmpty) {
          pc
              .setRemoteDescription(
                web.RTCSessionDescriptionInit(type: type, sdp: sdp),
              )
              .toDart
              .catchError((_) => null);
        }
      }
      return;
    }

    if (type == 'webrtc:candidate' && msg['candidate'] != null) {
      final c = msg['candidate'];
      if (c is Map) {
        final candidate = (c['candidate'] ?? '').toString();
        if (candidate.isEmpty) return;
        final sdpMid = c['sdpMid']?.toString();
        final idx = c['sdpMLineIndex'];
        final sdpMLineIndex = idx is int ? idx : int.tryParse('$idx');
        pc
            .addIceCandidate(
              web.RTCIceCandidateInit(
                candidate: candidate,
                sdpMid: sdpMid,
                sdpMLineIndex: sdpMLineIndex,
              ),
            )
            .toDart
            .catchError((_) => null);
      }
    }
  }

  Future<P2pApiResponse> sendRequest({
    required P2pRtcChannel channel,
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    final st = _requireChannel(channel);
    final dc = st.dc;
    await st.ready.future.timeout(const Duration(seconds: 15));
    if (dc.readyState != 'open') {
      throw Exception('p2p_dc_not_open');
    }
    final effectiveTimeout = timeout ?? const Duration(minutes: 5);

    bool aborted = false;

    Future<void> waitDrain() async {
      final limit = _sendDrainLimitBytes(channel);
      final startedAt = DateTime.now();
      while (dc.bufferedAmount > limit) {
        if (aborted) throw Exception('p2p_canceled');
        if (DateTime.now().difference(startedAt) >
            const Duration(seconds: 30)) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';
    final c = Completer<P2pApiResponse>();
    st.pending[id] = c;

    void abortLocal(Object error) {
      if (aborted) return;
      aborted = true;
      st.pending.remove(id);
      st.pendingChunks.remove(id);
      try {
        if (dc.readyState == 'open') {
          _sendControlMessage(st, {
            'type': '${st.prefix}:req:cancel',
            'id': id,
          });
        }
      } catch (_) {}
      if (!c.isCompleted) c.completeError(error);
    }

    if (cancelFuture != null) {
      cancelFuture
          .then((_) => abortLocal(Exception('p2p_canceled')))
          .catchError((_) => null);
    }

    final safeHeaders = <String, String>{};
    headers.forEach((k, v) {
      final key = k.trim();
      if (key.isEmpty) return;
      final lower = key.toLowerCase();
      if (lower == 'host' || lower == 'content-length') return;
      safeHeaders[key] = v;
    });

    final prefix = st.prefix;
    try {
      if (channel == P2pRtcChannel.api || channel == P2pRtcChannel.file) {
        await _yieldBulkBuffersBeforeHighPriorityControlSend();
      }
      final rawBody = bodyBytes is Uint8List
          ? bodyBytes
          : Uint8List.fromList(bodyBytes);
      if (rawBody.isNotEmpty) {
        if (aborted) throw Exception('p2p_canceled');
        await waitDrain();
        _sendControlMessage(st, {
          'type': '$prefix:req:begin',
          'id': id,
          'method': method,
          'path': path,
          'headers': safeHeaders,
          'length': rawBody.length,
        });
        final idBuf = utf8.encode(id);
        if (idBuf.length > 255) {
          throw Exception('p2p_req_id_too_long');
        }
        final idLen = idBuf.length;
        final header = Uint8List(2 + idLen);
        header[0] = 0x01;
        header[1] = idLen;
        header.setRange(2, header.length, idBuf);

        final chunkSize = _bodyChunkSize(channel);
        var chunkCount = 0;
        int offset = 0;
        while (offset < rawBody.length) {
          if (aborted) throw Exception('p2p_canceled');
          final end = min(offset + chunkSize, rawBody.length);
          final piece = Uint8List.sublistView(rawBody, offset, end);
          await waitDrain();
          final packet = Uint8List(header.length + piece.length);
          packet.setAll(0, header);
          packet.setRange(header.length, packet.length, piece);
          dc.send(packet.buffer.toJS);
          offset = end;
          chunkCount++;
          if (_hasHighPriorityContention() && _isBulkChannel(channel)) {
            if (chunkCount % 8 == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
        }
        if (aborted) throw Exception('p2p_canceled');
        await waitDrain();
        _sendControlMessage(st, {'type': '$prefix:req:end', 'id': id});
      } else {
        if (aborted) throw Exception('p2p_canceled');
        await waitDrain();
        _sendControlMessage(st, {
          'type': '$prefix:req',
          'id': id,
          'method': method,
          'path': path,
          'headers': safeHeaders,
        });
      }
    } catch (_) {
      st.pending.remove(id);
      st.pendingChunks.remove(id);
      rethrow;
    }

    try {
      return await c.future.timeout(effectiveTimeout);
    } finally {
      st.pending.remove(id);
    }
  }

  Future<P2pApiResponse> sendApiRequest({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    return sendRequest(
      channel: P2pRtcChannel.api,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
      cancelFuture: cancelFuture,
    );
  }

  Future<P2pApiResponse> sendFileRequest({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    return sendRequest(
      channel: P2pRtcChannel.file,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
      cancelFuture: cancelFuture,
    );
  }

  Future<P2pApiResponse> sendVideoRequest({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    return sendRequest(
      channel: P2pRtcChannel.video,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
      cancelFuture: cancelFuture,
    );
  }

  Future<P2pApiStreamResponse> sendRequestStream({
    required P2pRtcChannel channel,
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
  }) async {
    final st = _requireChannel(channel);
    final dc = st.dc;
    await st.ready.future.timeout(const Duration(seconds: 15));
    if (dc.readyState != 'open') {
      throw Exception('p2p_dc_not_open');
    }
    final prefix = st.prefix;

    Future<void> waitDrain() async {
      final limit = _streamSendDrainLimitBytes(channel);
      final startedAt = DateTime.now();
      while (dc.bufferedAmount > limit) {
        if (DateTime.now().difference(startedAt) >
            const Duration(seconds: 30)) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 30)}';

    Timer? flowPauseTimer;
    bool flowPaused = false;
    void sendFlow(String action) {
      final cur = dc;
      if (cur.readyState != 'open') return;
      try {
        _sendControlMessage(st, {
          'type': '$prefix:flow',
          'id': id,
          'action': action,
        });
      } catch (_) {}
    }

    late void Function() cancel;
    final controller = StreamController<Uint8List>(
      sync: true,
      onCancel: () {
        try {
          flowPauseTimer?.cancel();
        } catch (_) {}
        try {
          cancel();
        } catch (_) {}
      },
      onListen: () {
        try {
          flowPauseTimer?.cancel();
        } catch (_) {}
        if (flowPaused) {
          flowPaused = false;
          sendFlow('resume');
        }
      },
      onPause: () {
        flowPauseTimer?.cancel();
        if (flowPaused) return;
        flowPauseTimer = Timer(const Duration(seconds: 3), () {
          if (flowPaused) return;
          flowPaused = true;
          sendFlow('pause');
        });
      },
      onResume: () {
        flowPauseTimer?.cancel();
        if (flowPaused) {
          flowPaused = false;
          sendFlow('resume');
        }
      },
    );
    final start = Completer<_StreamStart>();
    st.pendingStreams[id] = _PendingStream(
      controller: controller,
      start: start,
    );

    final safeHeaders = <String, String>{};
    headers.forEach((k, v) {
      final key = k.trim();
      if (key.isEmpty) return;
      final lower = key.toLowerCase();
      if (lower == 'host' || lower == 'content-length') return;
      safeHeaders[key] = v;
    });

    void cancelInternal() {
      final pst = st.pendingStreams.remove(id);
      if (pst == null) return;
      try {
        if (dc.readyState == 'open') {
          _sendControlMessage(st, {'type': '$prefix:cancel', 'id': id});
        }
      } catch (_) {}
      if (!pst.start.isCompleted) {
        pst.start.completeError(Exception('p2p_canceled'));
      }
      _failP2pStreamBody(pst.controller, Exception('p2p_canceled'));
    }

    cancel = cancelInternal;

    try {
      if (channel == P2pRtcChannel.api || channel == P2pRtcChannel.file) {
        await _yieldBulkBuffersBeforeHighPriorityControlSend();
      }
      final rawBody = bodyBytes is Uint8List
          ? bodyBytes
          : Uint8List.fromList(bodyBytes);
      if (rawBody.isNotEmpty) {
        await waitDrain();
        _sendControlMessage(st, {
          'type': '$prefix:req:begin',
          'id': id,
          'method': method,
          'path': path,
          'headers': safeHeaders,
          'length': rawBody.length,
        });
        final idBuf = utf8.encode(id);
        if (idBuf.length > 255) {
          throw Exception('p2p_req_id_too_long');
        }
        final idLen = idBuf.length;
        final header = Uint8List(2 + idLen);
        header[0] = 0x01;
        header[1] = idLen;
        header.setRange(2, header.length, idBuf);

        final chunkSize = _bodyChunkSize(channel);
        var chunkCount = 0;
        int offset = 0;
        while (offset < rawBody.length) {
          final end = min(offset + chunkSize, rawBody.length);
          final piece = Uint8List.sublistView(rawBody, offset, end);
          await waitDrain();
          final packet = Uint8List(header.length + piece.length);
          packet.setAll(0, header);
          packet.setRange(header.length, packet.length, piece);
          dc.send(packet.buffer.toJS);
          offset = end;
          chunkCount++;
          if (_hasHighPriorityContention() && _isBulkChannel(channel)) {
            if (chunkCount % 8 == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
        }
        await waitDrain();
        _sendControlMessage(st, {'type': '$prefix:req:end', 'id': id});
      } else {
        await waitDrain();
        _sendControlMessage(st, {
          'type': '$prefix:req',
          'id': id,
          'method': method,
          'path': path,
          'headers': safeHeaders,
        });
      }
    } catch (_) {
      cancel();
      rethrow;
    }

    final effectiveTimeout = timeout ?? const Duration(minutes: 5);
    Timer(effectiveTimeout, () {
      if (st.pendingStreams.containsKey(id)) cancelInternal();
    });

    _StreamStart started;
    try {
      final startTimeout = effectiveTimeout < const Duration(seconds: 15)
          ? effectiveTimeout
          : const Duration(seconds: 15);
      started = await start.future.timeout(startTimeout);
    } on TimeoutException {
      cancelInternal();
      throw Exception('p2p_dc_error_start_timeout');
    } catch (_) {
      cancelInternal();
      rethrow;
    }
    return P2pApiStreamResponse(
      status: started.status,
      headers: started.headers,
      stream: controller.stream,
      cancel: cancelInternal,
    );
  }

  Future<P2pApiStreamResponse> sendApiRequestStream({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
  }) async {
    return sendRequestStream(
      channel: P2pRtcChannel.api,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
    );
  }

  Future<P2pApiStreamResponse> sendFileRequestStream({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
  }) async {
    return sendRequestStream(
      channel: P2pRtcChannel.file,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
    );
  }

  Future<P2pApiStreamResponse> sendVideoRequestStream({
    required String method,
    required String path,
    required Map<String, String> headers,
    required List<int> bodyBytes,
    Duration? timeout,
  }) async {
    return sendRequestStream(
      channel: P2pRtcChannel.video,
      method: method,
      path: path,
      headers: headers,
      bodyBytes: bodyBytes,
      timeout: timeout,
    );
  }

  Future<void> close() async {
    try {
      _apiHeartbeatTimer?.cancel();
    } catch (_) {}
    _apiHeartbeatTimer = null;

    try {
      for (final st in _channels.values) {
        final pending = List<Completer<P2pApiResponse>>.from(st.pending.values);
        for (final c in pending) {
          if (!c.isCompleted) c.completeError(Exception('p2p_disconnected'));
        }
        st.pending.clear();
        st.pendingChunks.clear();
        final pendingStreams = List<_PendingStream>.from(
          st.pendingStreams.values,
        );
        for (final pst in pendingStreams) {
          if (!pst.start.isCompleted) {
            pst.start.completeError(Exception('p2p_disconnected'));
          }
          _failP2pStreamBody(pst.controller, Exception('p2p_disconnected'));
        }
        st.pendingStreams.clear();
        try {
          st.dc.close();
        } catch (_) {}
      }
    } catch (_) {}
    _channels.clear();

    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
  }
}

class _PendingChunk {
  _PendingChunk({
    required this.completer,
    required this.status,
    required this.headers,
    required this.builder,
    required this.length,
  });

  final Completer<P2pApiResponse> completer;
  final int status;
  final Map<String, String> headers;
  final BytesBuilder builder;
  final int length;
  /// 分块响应 ACK 聚合（与流式 pendingStreams 逻辑对齐）。
  int chunkAckPendingBytes = 0;
  bool chunkAckScheduled = false;
  int lastAckSentMs = 0;
}

class _StreamStart {
  _StreamStart({required this.status, required this.headers});

  final int status;
  final Map<String, String> headers;
}

class _PendingStream {
  _PendingStream({required this.controller, required this.start});

  final StreamController<Uint8List> controller;
  final Completer<_StreamStart> start;
  int ackPendingBytes = 0;
  bool ackScheduled = false;
  /// download 通道 ACK 最小间隔（与 lastAckSentMs 配合），降低 SCTP 上控制帧频率。
  int lastAckSentMs = 0;
}

class _RtcChannelState {
  final P2pRtcChannel channel;
  final String prefix;
  final web.RTCDataChannel dc;
  final Completer<void> ready;
  final Map<String, Completer<P2pApiResponse>> pending = {};
  final Map<String, _PendingChunk> pendingChunks = {};
  final Map<String, _PendingStream> pendingStreams = {};
  final Map<String, _P2pRtcWebSocketChannel> wsTunnels = {};
  Future<void> rxQueue = Future<void>.value();
  int txPackets = 0;
  int txBytes = 0;
  int rxPackets = 0;
  int rxBytes = 0;
  int lastTxAtMs = 0;
  int lastRxAtMs = 0;
  String? cachedChunkId;
  Uint8List? cachedChunkIdBytes;
  bool supportsChunkBinaryV2 = false;

  _RtcChannelState({
    required this.channel,
    required this.prefix,
    required this.dc,
    required this.ready,
  });
}

class _P2pRtcWebSocketChannel
    with StreamChannelMixin
    implements WebSocketChannel {
  _P2pRtcWebSocketChannel({
    required this.id,
    required this.prefix,
    required this.sendJson,
    required this.onClose,
  }) : _delegate = StreamController<dynamic>(sync: true),
       _incoming = StreamController<dynamic>(sync: true),
       _ready = Completer<void>() {
    sink = _P2pRtcWebSocketSink(
      _delegate.sink,
      onAdd: _handleOutgoingAdd,
      onClose: (code, reason) => _closeLocal(code, reason),
    );
  }

  final String id;
  final String prefix;
  final void Function(Map<String, dynamic>) sendJson;
  final void Function() onClose;

  final StreamController<dynamic> _delegate;
  final StreamController<dynamic> _incoming;
  final Completer<void> _ready;
  final List<dynamic> _pendingOutgoing = <dynamic>[];
  bool _closed = false;

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream get stream => _incoming.stream;

  @override
  late final WebSocketSink sink;

  void _sendOpen(String path, Map<String, String> headers) {
    if (_closed) return;
    sendJson({
      'type': '$prefix:ws:open',
      'id': id,
      'path': path,
      'headers': headers,
    });
  }

  void _handleOutgoingAdd(dynamic data) {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _pendingOutgoing.add(data);
      return;
    }
    final payload = data is String ? data : jsonEncode(data);
    try {
      sendJson({'type': '$prefix:ws:send', 'id': id, 'data': payload});
    } catch (_) {}
  }

  void _flushPending() {
    if (_closed) return;
    if (!_ready.isCompleted) return;
    if (_pendingOutgoing.isEmpty) return;
    final list = List<dynamic>.from(_pendingOutgoing);
    _pendingOutgoing.clear();
    for (final m in list) {
      _handleOutgoingAdd(m);
    }
  }

  void _handleOpenOk() {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.complete();
    _flushPending();
  }

  void _handleOpenError(String error) {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.completeError(Exception(error));
    _closeLocal(1011, error);
  }

  void _handleMessage(String data) {
    if (_closed) return;
    _incoming.add(data);
  }

  void _handleRemoteError(String error) {
    if (_closed) return;
    if (!_ready.isCompleted) _ready.completeError(Exception(error));
    _closeLocal(1011, error);
  }

  void _handleRemoteClose(int? code, String? reason) {
    closeCode = code;
    closeReason = reason;
    _finalizeClose();
  }

  Future<void> _closeLocal(int? code, String? reason) async {
    if (_closed) return;
    try {
      sendJson({'type': '$prefix:ws:close', 'id': id});
    } catch (_) {}
    closeCode ??= code;
    closeReason ??= reason;
    _finalizeClose();
  }

  void _finalizeClose() {
    if (_closed) return;
    _closed = true;
    onClose();
    try {
      _incoming.close();
    } catch (_) {}
    try {
      _delegate.close();
    } catch (_) {}
  }
}

class _P2pRtcWebSocketSink extends DelegatingStreamSink<dynamic>
    implements WebSocketSink {
  _P2pRtcWebSocketSink(
    super.sink, {
    required void Function(dynamic data) onAdd,
    required Future<void> Function(int? code, String? reason) onClose,
  }) : _onAdd = onAdd,
       _onClose = onClose;

  final void Function(dynamic data) _onAdd;
  final Future<void> Function(int? code, String? reason) _onClose;

  @override
  void add(dynamic data) {
    _onAdd(data);
  }

  @override
  Future addStream(Stream stream) async {
    await for (final data in stream) {
      _onAdd(data);
    }
  }

  @override
  Future close([int? closeCode, String? closeReason]) {
    return _onClose(closeCode, closeReason);
  }
}

class _IntRef {
  _IntRef(this.value);
  int value;
}
