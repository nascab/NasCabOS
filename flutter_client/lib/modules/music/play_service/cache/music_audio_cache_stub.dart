import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import '../../../../core/api/api_controller.dart';
import '../player/music_player_adapter.dart';

class MusicAudioCacheOptions {
  final bool enabled;
  final int maxItems;

  const MusicAudioCacheOptions({required this.enabled, required this.maxItems});

  MusicAudioCacheOptions copyWith({bool? enabled, int? maxItems}) {
    return MusicAudioCacheOptions(
      enabled: enabled ?? this.enabled,
      maxItems: maxItems ?? this.maxItems,
    );
  }
}

class MusicAudioCacheProgress {
  final int receivedBytes;
  final int totalBytes;
  final bool finished;

  const MusicAudioCacheProgress({
    required this.receivedBytes,
    required this.totalBytes,
    this.finished = false,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    final p = receivedBytes / totalBytes;
    if (p.isNaN || p.isInfinite) return 0;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }
}

typedef MusicAudioCacheProgressCallback =
    void Function(MusicAudioCacheProgress progress);

class MusicAudioCacheCanceled implements Exception {}

class MusicAudioCacheStats {
  final int count;
  final int totalBytes;

  const MusicAudioCacheStats({required this.count, required this.totalBytes});
}

class MusicAudioCacheService {
  MusicAudioCacheOptions options;

  MusicAudioCacheService({required this.options});

  final Map<String, String> _webObjectUrls = {};

  Future<void> init() async {}

  void updateOptions(MusicAudioCacheOptions options) {
    this.options = options;
  }

  Future<MusicAudioCacheStats> getStats() async {
    return const MusicAudioCacheStats(count: 0, totalBytes: 0);
  }

  Future<void> clearAll() async {
    if (!kIsWeb) return;
    for (final u in _webObjectUrls.values) {
      try {
        web.URL.revokeObjectURL(u);
      } catch (_) {}
    }
    _webObjectUrls.clear();
  }

  Future<void> remove(String fileHash) async {
    if (!kIsWeb) return;
    final key = fileHash.trim();
    if (key.isEmpty) return;
    final u = _webObjectUrls.remove(key);
    if (u == null || u.isEmpty) return;
    try {
      web.URL.revokeObjectURL(u);
    } catch (_) {}
  }

  bool get isDownloading => false;

  String? get activeHash => null;

  Future<void> cancelActiveDownload() async {}

  Future<bool> hasCached(String fileHash) async {
    return false;
  }

  Future<MusicPlaySource> prepareSource({
    required String fileHash,
    required String fileExt,
    required int fileSize,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    final url = await buildUrl();
    return MusicPlaySource(url: url, fileExt: fileExt);
  }

  Future<VideoPlayerController> prepareController({
    required String fileHash,
    required String fileExt,
    required int fileSize,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    final url = await buildUrl();
    if (kIsWeb && ApiController.instance.isP2pMode) {
      final hash = fileHash.trim();
      final existing = hash.isEmpty ? null : _webObjectUrls[hash];
      if (existing != null && existing.isNotEmpty) {
        return VideoPlayerController.networkUrl(Uri.parse(existing));
      }

      String p2pPath = '';
      try {
        final uri = Uri.parse(url);
        p2pPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      } catch (_) {
        p2pPath = '';
      }

      if (p2pPath.isNotEmpty) {
        final req = http.Request(
          'GET',
          Uri.parse(
            '${ApiController.p2pBaseUrl}'
            '${p2pPath.startsWith('/') ? p2pPath : '/$p2pPath'}',
          ),
        );
        final token = ApiController.instance.accessToken?.trim() ?? '';
        if (token.isNotEmpty) {
          req.headers['Authorization'] = 'Bearer $token';
        }

        final streamed = await ApiController.instance.sendP2pRequest(req);
        final bytes = await streamed.stream.toBytes();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          throw Exception('p2p_audio_http_${streamed.statusCode}');
        }

        var mime = streamed.headers['content-type']?.trim() ?? '';
        if (mime.isEmpty) {
          mime = _guessAudioMime(fileExt);
        } else {
          final semi = mime.indexOf(';');
          if (semi != -1) {
            mime = mime.substring(0, semi).trim();
          }
        }
        final jsBuf = Uint8List.fromList(bytes).buffer.toJS;
        final blob = web.Blob([jsBuf].toJS, web.BlobPropertyBag(type: mime));
        final objUrl = web.URL.createObjectURL(blob);
        if (hash.isNotEmpty) {
          _webObjectUrls[hash] = objUrl;
        }
        return VideoPlayerController.networkUrl(Uri.parse(objUrl));
      }
    }

    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
}

String _guessAudioMime(String fileExt) {
  final e = fileExt.trim().toLowerCase();
  if (e == 'mp3') return 'audio/mpeg';
  if (e == 'aac') return 'audio/aac';
  if (e == 'm4a' || e == 'mp4') return 'audio/mp4';
  if (e == 'wav') return 'audio/wav';
  if (e == 'ogg' || e == 'opus') return 'audio/ogg';
  if (e == 'flac') return 'audio/flac';
  return 'application/octet-stream';
}
