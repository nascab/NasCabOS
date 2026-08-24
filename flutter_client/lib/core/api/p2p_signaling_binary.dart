// P2P 信令紧凑二进制协议（与服务端 signalingBinary.js / quickshare 一致）

import 'dart:convert';
import 'dart:typed_data';

const List<int> _magic = [0x4e, 0x50, 0x53, 0x01]; // NPS\x01

const int _typePing = 0x01;
const int _typePong = 0x02;
const int _typeSessionReady = 0x10;
const int _typeSessionClosed = 0x11;
const int _typeWebrtcOffer = 0x20;
const int _typeWebrtcAnswer = 0x21;
const int _typeWebrtcCandidate = 0x22;
const int _typeError = 0x23;
const int _typeDeviceReady = 0x30;
const int _typeDevicePairCode = 0x31;
const int _typeSessionClientConnected = 0x32;
const int _typeWebrtcDeviceReady = 0x33;

Uint8List _encodeVarint(int n) {
  int v = n < 0 ? 0 : n;
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.add(v & 0xff);
  return Uint8List.fromList(out);
}

/// Returns (value, nextOffset) or null.
(int, int)? _decodeVarint(Uint8List buf, int offset0) {
  int offset = offset0;
  int shift = 0;
  int result = 0;
  while (offset < buf.length) {
    final b = buf[offset] & 0xff;
    offset += 1;
    result |= (b & 0x7f) << shift;
    if ((b & 0x80) == 0) return (result, offset);
    shift += 7;
    if (shift > 35) return null;
  }
  return null;
}

Uint8List _encodeString(String s) {
  final b = utf8.encode(s);
  return Uint8List.fromList([..._encodeVarint(b.length), ...b]);
}

/// Returns (string, nextOffset) or null.
(String, int)? _decodeString(Uint8List buf, int offset0) {
  final v = _decodeVarint(buf, offset0);
  if (v == null) return null;
  final len = v.$1;
  int offset = v.$2;
  final end = offset + len;
  if (end > buf.length) return null;
  final str = len == 0 ? '' : utf8.decode(buf.sublist(offset, end));
  return (str, end);
}

bool isSignalingBinary(Uint8List buf) {
  if (buf.length < 5) return false;
  return buf[0] == _magic[0] &&
      buf[1] == _magic[1] &&
      buf[2] == _magic[2] &&
      buf[3] == _magic[3];
}

/// 将 [msg] 编码为与服务端一致的二进制；失败返回 null。
Uint8List? encodeSignaling(Map<String, dynamic> msg) {
  final type = msg['type']?.toString() ?? '';
  int mt;
  switch (type) {
    case 'ping':
      mt = _typePing;
      break;
    case 'pong':
      mt = _typePong;
      break;
    case 'session:ready':
      mt = _typeSessionReady;
      break;
    case 'session:closed':
      mt = _typeSessionClosed;
      break;
    case 'webrtc:offer':
      mt = _typeWebrtcOffer;
      break;
    case 'webrtc:answer':
      mt = _typeWebrtcAnswer;
      break;
    case 'webrtc:candidate':
      mt = _typeWebrtcCandidate;
      break;
    case 'error':
      mt = _typeError;
      break;
    case 'device:ready':
      mt = _typeDeviceReady;
      break;
    case 'device:pairCode':
      mt = _typeDevicePairCode;
      break;
    case 'session:client_connected':
      mt = _typeSessionClientConnected;
      break;
    case 'webrtc:device_ready':
      mt = _typeWebrtcDeviceReady;
      break;
    default:
      return null;
  }

  final parts = <int>[..._magic, mt];

  if (mt == _typePing || mt == _typePong) {
    final ts = (msg['ts'] is int)
        ? msg['ts'] as int
        : (msg['ts'] != null ? int.tryParse(msg['ts'].toString()) ?? 0 : 0);
    parts.addAll(_encodeVarint(ts));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeSessionReady) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    final ice = msg['iceServers'];
    final iceJson = ice is List
        ? jsonEncode(ice)
        : (ice != null ? ice.toString() : '[]');
    parts.addAll(_encodeString(iceJson));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeSessionClosed) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    parts.addAll(_encodeString(msg['reason']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeWebrtcOffer) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    final offer = msg['offer'];
    final o = offer is Map ? offer : <String, dynamic>{};
    parts.addAll(_encodeString(o['type']?.toString() ?? ''));
    parts.addAll(_encodeString(o['sdp']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeWebrtcAnswer) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    final answer = msg['answer'];
    final a = answer is Map ? answer : <String, dynamic>{};
    parts.addAll(_encodeString(a['type']?.toString() ?? ''));
    parts.addAll(_encodeString(a['sdp']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeWebrtcCandidate) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    final c = msg['candidate'];
    final cand = c is Map ? c : <String, dynamic>{};
    parts.addAll(_encodeString(cand['candidate']?.toString() ?? ''));
    parts.addAll(_encodeString(cand['sdpMid']?.toString() ?? ''));
    final idx = cand['sdpMLineIndex'];
    parts.addAll(
      _encodeVarint(
        idx is int ? idx : (int.tryParse(idx?.toString() ?? '0') ?? 0),
      ),
    );
    return Uint8List.fromList(parts);
  }
  if (mt == _typeError) {
    parts.addAll(_encodeString(msg['code']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeDeviceReady || mt == _typeDevicePairCode) {
    parts.addAll(_encodeString(msg['deviceId']?.toString() ?? ''));
    parts.addAll(_encodeString(msg['serverId']?.toString() ?? ''));
    parts.addAll(_encodeString(msg['pairCode']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeSessionClientConnected) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    final ice = msg['iceServers'];
    final iceJson = ice is List
        ? jsonEncode(ice)
        : (ice != null ? ice.toString() : '[]');
    parts.addAll(_encodeString(iceJson));
    return Uint8List.fromList(parts);
  }
  if (mt == _typeWebrtcDeviceReady) {
    parts.addAll(_encodeString(msg['sessionId']?.toString() ?? ''));
    return Uint8List.fromList(parts);
  }
  return null;
}

/// 解码二进制信令；非 NPS 或解析失败返回 null。
Map<String, dynamic>? decodeSignaling(Uint8List buf) {
  if (buf.length < 5 || !isSignalingBinary(buf)) return null;
  final mt = buf[4] & 0xff;
  int offset = 5;

  String? readStr() {
    final r = _decodeString(buf, offset);
    if (r == null) return null;
    offset = r.$2;
    return r.$1;
  }

  int? readVar() {
    final r = _decodeVarint(buf, offset);
    if (r == null) return null;
    offset = r.$2;
    return r.$1;
  }

  if (mt == _typePing) {
    final ts = readVar();
    if (ts == null) return null;
    return {'type': 'ping', 'ts': ts};
  }
  if (mt == _typePong) {
    final ts = readVar();
    if (ts == null) return null;
    return {'type': 'pong', 'ts': ts};
  }
  if (mt == _typeSessionReady) {
    final sessionId = readStr();
    final iceJson = readStr();
    if (sessionId == null || iceJson == null) return null;
    List<dynamic> iceServers = [];
    try {
      final decoded = jsonDecode(iceJson);
      if (decoded is List) iceServers = decoded;
    } catch (_) {}
    return {
      'type': 'session:ready',
      'sessionId': sessionId,
      'iceServers': iceServers,
    };
  }
  if (mt == _typeSessionClosed) {
    final sessionId = readStr();
    final reason = readStr();
    if (sessionId == null) return null;
    return {
      'type': 'session:closed',
      'sessionId': sessionId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    };
  }
  if (mt == _typeWebrtcOffer) {
    final sessionId = readStr();
    final type = readStr();
    final sdp = readStr();
    if (sessionId == null || type == null || sdp == null) return null;
    return {
      'type': 'webrtc:offer',
      'sessionId': sessionId,
      'offer': {'type': type, 'sdp': sdp},
    };
  }
  if (mt == _typeWebrtcAnswer) {
    final sessionId = readStr();
    final type = readStr();
    final sdp = readStr();
    if (type == null || sdp == null) return null;
    return {
      'type': 'webrtc:answer',
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
      'answer': {'type': type, 'sdp': sdp},
    };
  }
  if (mt == _typeWebrtcCandidate) {
    final sessionId = readStr();
    final candidate = readStr();
    final sdpMid = readStr();
    final sdpMLineIndex = readVar();
    if (sessionId == null || candidate == null) return null;
    return {
      'type': 'webrtc:candidate',
      'sessionId': sessionId,
      'candidate': {
        'candidate': candidate,
        'sdpMid': sdpMid ?? '',
        'sdpMLineIndex': sdpMLineIndex ?? 0,
      },
    };
  }
  if (mt == _typeError) {
    final code = readStr();
    if (code == null) return null;
    return {'type': 'error', 'code': code};
  }
  if (mt == _typeDeviceReady) {
    final deviceId = readStr();
    final serverId = readStr();
    final pairCode = readStr();
    if (deviceId == null || serverId == null || pairCode == null) return null;
    return {
      'type': 'device:ready',
      'deviceId': deviceId,
      'serverId': serverId,
      'pairCode': pairCode,
    };
  }
  if (mt == _typeDevicePairCode) {
    final deviceId = readStr();
    final serverId = readStr();
    final pairCode = readStr();
    if (deviceId == null || serverId == null || pairCode == null) return null;
    return {
      'type': 'device:pairCode',
      'deviceId': deviceId,
      'serverId': serverId,
      'pairCode': pairCode,
    };
  }
  if (mt == _typeSessionClientConnected) {
    final sessionId = readStr();
    final iceJson = readStr();
    if (sessionId == null || iceJson == null) return null;
    List<dynamic> iceServers = [];
    try {
      final decoded = jsonDecode(iceJson);
      if (decoded is List) iceServers = decoded;
    } catch (_) {}
    return {
      'type': 'session:client_connected',
      'sessionId': sessionId,
      'iceServers': iceServers,
    };
  }
  if (mt == _typeWebrtcDeviceReady) {
    final sessionId = readStr();
    if (sessionId == null) return null;
    return {'type': 'webrtc:device_ready', 'sessionId': sessionId};
  }
  return null;
}

/// 将 stream 事件转为 Uint8List（支持 Uint8List / ByteBuffer / List of int / String），再解码；非二进制或解码失败返回 null。
Map<String, dynamic>? decodeSignalingFromEvent(dynamic event) {
  Uint8List bytes;
  if (event is Uint8List) {
    bytes = event;
  } else if (event is ByteBuffer) {
    bytes = event.asUint8List();
  } else if (event is List<int>) {
    bytes = Uint8List.fromList(event);
  } else if (event is String) {
    final s = event;
    if (s.isEmpty) return null;
    final out = Uint8List(s.length);
    for (var i = 0; i < s.length; i++) {
      out[i] = s.codeUnitAt(i) & 0xff;
    }
    bytes = out;
  } else {
    return null;
  }
  if (bytes.isEmpty) return null;
  return decodeSignaling(bytes);
}
