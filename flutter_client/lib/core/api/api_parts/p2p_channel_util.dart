import '../p2p_rtc_stub.dart' if (dart.library.html) '../p2p_rtc_web.dart';

class P2pChannelUtil {
  static P2pRtcChannel? parseMark(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'api') return P2pRtcChannel.api;
    if (s == 'file') return P2pRtcChannel.file;
    if (s == 'upload') return P2pRtcChannel.upload;
    if (s == 'download') return P2pRtcChannel.download;
    if (s == 'video') return P2pRtcChannel.video;
    return null;
  }

  static P2pRtcChannel fallbackForPath(String path) {
    final p = path.trim();
    if (p.startsWith('/api/file/upload')) return P2pRtcChannel.upload;
    if (p.startsWith('/api/file/download')) return P2pRtcChannel.download;
    if (p.startsWith('/api/videoPlayer/')) return P2pRtcChannel.video;
    if (p.startsWith('/api/file/rawFile')) return P2pRtcChannel.file;
    if (p.startsWith('/api/file') || p.startsWith('/api/static')) {
      return P2pRtcChannel.file;
    }
    return P2pRtcChannel.api;
  }

  static String stripP2pChannelFromPath(String path) {
    return stripQueryKey(path, 'p2pChannel');
  }

  static String stripQueryKey(String path, String key) {
    final idx = path.indexOf('?');
    if (idx < 0) return path;
    final base = path.substring(0, idx);
    final query = path.substring(idx + 1);
    if (query.trim().isEmpty) return base;
    final parts = query.split('&');
    final kept = <String>[];
    for (final part in parts) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      final k = (eq >= 0 ? p.substring(0, eq) : p).trim();
      if (k == key) continue;
      kept.add(p);
    }
    if (kept.isEmpty) return base;
    return '$base?${kept.join('&')}';
  }

  static ({P2pRtcChannel channel, String path}) resolve({
    required Uri uri,
    P2pRtcChannel? fallbackChannel,
  }) {
    final rawPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final stripped = stripP2pChannelFromPath(rawPath);
    final mark = parseMark(uri.queryParameters['p2pChannel']);
    final fallback = fallbackChannel ?? fallbackForPath(uri.path);
    return (channel: mark ?? fallback, path: stripped);
  }
}
