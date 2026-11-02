import 'dart:async';
import 'dart:io';

import 'package:NasCabOS/utils/local_web_asset_server.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'music_player_adapter.dart';

/// 通过本地 HTTP 代理获取音频数据，并向 just_audio 提供正确的 MIME 类型，
/// 解决 iOS AVPlayer 无法从 /api/file/rawFile 路径推断格式的问题。
class _ProxyStreamAudioSource extends StreamAudioSource {
  final String proxyUrl;
  final String mimeType;

  _ProxyStreamAudioSource({required this.proxyUrl, required this.mimeType});

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(proxyUrl));

      if (start != null || end != null) {
        final s = start ?? 0;
        if (end != null) {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$s-${end - 1}');
        } else {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$s-');
        }
      }

      // 本地代理在 P2P 未就绪时最多等待 12s 再返回 503，这里加超时
      // 防止切歌时整个打开流程无限挂起。
      final resp = await req.close().timeout(const Duration(seconds: 30));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        client.close(force: true);
        // 显式抛错，让 just_audio 走错误回调而不是把 503 JSON 当音频解码
        throw Exception('audio_source_http_${resp.statusCode}');
      }

      int? sourceLength;
      final cr = resp.headers.value(HttpHeaders.contentRangeHeader);
      if (cr != null) {
        final m = RegExp(r'/(\d+)$').firstMatch(cr);
        if (m != null) sourceLength = int.tryParse(m.group(1)!);
      }
      if (sourceLength == null &&
          resp.statusCode == 200 &&
          resp.contentLength > 0) {
        sourceLength = resp.contentLength;
      }

      final offset = start ?? 0;
      var contentLength = 0;
      if (end != null) {
        contentLength = end - offset;
      } else if (sourceLength != null && sourceLength > offset) {
        contentLength = sourceLength - offset;
      } else if (resp.contentLength > 0) {
        contentLength = resp.contentLength;
      }

      final stream = resp.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleDone: (sink) {
            client.close();
            sink.close();
          },
          handleError: (error, stackTrace, sink) {
            client.close(force: true);
            sink.addError(error, stackTrace);
            sink.close();
          },
        ),
      );

      return StreamAudioResponse(
        sourceLength: sourceLength,
        contentLength: contentLength,
        offset: offset,
        stream: stream,
        contentType: mimeType,
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

String _guessMimeType(String ext) {
  final e = ext.trim().toLowerCase();
  if (e == 'mp3') return 'audio/mpeg';
  if (e == 'aac') return 'audio/aac';
  if (e == 'm4a' || e == 'mp4') return 'audio/mp4';
  if (e == 'wav') return 'audio/wav';
  if (e == 'ogg' || e == 'opus') return 'audio/ogg';
  if (e == 'flac') return 'audio/flac';
  if (e == 'wma') return 'audio/x-ms-wma';
  if (e == 'ape') return 'audio/x-ape';
  if (e == 'aiff' || e == 'aif') return 'audio/aiff';
  if (e == 'alac') return 'audio/mp4';
  return 'audio/mpeg';
}

/// 使用 just_audio 的实现（iOS、Android），支持后台与锁屏播放
class MusicPlayerJustAudioAdapter extends MusicPlayerAdapter {
  MusicPlayerJustAudioAdapter();

  final AudioPlayer _player = AudioPlayer();
  bool _proxyAcquired = false;
  bool _hasError = false;
  ProcessingState? _lastProcessingState;

  VoidCallback? _listener;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  Future<void> initialize() async {}

  Future<void> loadFromSource(MusicPlaySource source) async {
    _hasError = false;
    if (_proxyAcquired) {
      _proxyAcquired = false;
      await LocalWebAssetServer.instance.release();
    }
    if (source.isLocal && source.filePath != null) {
      await _player.setFilePath(source.filePath!);
    } else {
      var playbackUrl = source.url;
      final raw = playbackUrl.trim();
      if (raw.startsWith('http')) {
        Uri remote;
        try {
          remote = Uri.parse(raw);
        } catch (_) {
          remote = Uri();
        }
        if (remote.path.isNotEmpty) {
          final localBase = await LocalWebAssetServer.instance.acquire();
          _proxyAcquired = true;
          playbackUrl = localBase
              .replace(path: remote.path, query: remote.query)
              .toString();
        }
      }
      final mimeType = _guessMimeType(source.fileExt);
      try {
        await _player.setAudioSource(
          _ProxyStreamAudioSource(proxyUrl: playbackUrl, mimeType: mimeType),
        );
      } catch (_) {
        _hasError = true;
        if (_proxyAcquired) {
          _proxyAcquired = false;
          await LocalWebAssetServer.instance.release();
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double value) => _player.setVolume(value);

  @override
  Future<void> setLooping(bool looping) =>
      _player.setLoopMode(looping ? LoopMode.one : LoopMode.off);

  void _notify() => _listener?.call();

  @override
  void addListener(VoidCallback listener) {
    _listener = listener;
    _subs.add(
      _player.playerStateStream.listen((state) {
        _lastProcessingState = state.processingState;
        _notify();
      }),
    );
    // 播放过程中的错误（如 P2P 建流失败/中断）需要上报给控制器触发恢复
    _subs.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _hasError = true;
          _notify();
        },
      ),
    );
    _subs.add(_player.positionStream.listen((_) => _notify()));
    _subs.add(_player.durationStream.listen((_) => _notify()));
  }

  @override
  void removeListener(VoidCallback listener) {
    _listener = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
    if (_proxyAcquired) {
      _proxyAcquired = false;
      await LocalWebAssetServer.instance.release();
    }
  }

  @override
  Duration get duration => _player.duration ?? Duration.zero;

  @override
  Duration get position => _player.position;

  @override
  Duration get buffered => _player.bufferedPosition;

  @override
  bool get isPlaying => _player.playing;

  @override
  bool get isBuffering =>
      _player.processingState == ProcessingState.buffering ||
      _player.processingState == ProcessingState.loading;

  @override
  bool get hasError => _hasError;

  @override
  bool get isInitialized =>
      _player.processingState != ProcessingState.idle &&
      _player.processingState != ProcessingState.loading;

  /// 专门针对 just_audio 的完成状态检测
  @override
  bool get isCompleted => _lastProcessingState == ProcessingState.completed;
}
