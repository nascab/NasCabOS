import 'package:NasCabOS/modules/video_player/cache/video_range_memory_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoRangeMemoryCache.parseRangeHeader', () {
    test('parse fixed range', () {
      final r = VideoRangeMemoryCache.parseRangeHeader('bytes=0-1023', 10000);
      expect(r, isNotNull);
      expect(r!.start, 0);
      expect(r.end, 1023);
    });

    test('parse open ended with file size', () {
      final r = VideoRangeMemoryCache.parseRangeHeader('bytes=512-', 2048);
      expect(r, isNotNull);
      expect(r!.start, 512);
      expect(r.end, 2047);
      expect(r.openEnded, isTrue);
    });

    test('parse suffix range', () {
      final r = VideoRangeMemoryCache.parseRangeHeader('bytes=-500', 10000);
      expect(r, isNotNull);
      expect(r!.start, 9500);
      expect(r.end, 9999);
    });

    test('suffix without file size returns null', () {
      final r = VideoRangeMemoryCache.parseRangeHeader('bytes=-500', null);
      expect(r, isNull);
    });
  });

  group('VideoRangeMemoryCache cache coverage', () {
    test('hasCachedByteAt and prefix after ingest', () {
      final cache = VideoRangeMemoryCache(
        sessionKey: 'test',
        options: const VideoRangeCacheOptions(blockSize: 1024),
      );
      cache.bindFileSize(10000);
      expect(cache.hasCachedByteAt(0), isFalse);

      cache.ingestBytes(0, List<int>.filled(2048, 7));
      expect(cache.hasCachedByteAt(0), isTrue);
      expect(cache.hasCachedByteAt(1500), isTrue);
      expect(cache.hasCachedByteAt(2500), isFalse);
      expect(cache.cachedPrefixLength(0, 1999), 2000);
      expect(cache.isRangeFullyCached(0, 1023), isTrue);
    });

    test('upstream span fully cached', () {
      final cache = VideoRangeMemoryCache(
        sessionKey: 'test',
        options: const VideoRangeCacheOptions(blockSize: 256),
      );
      cache.bindFileSize(5000);
      cache.ingestBytes(1000, List<int>.filled(3000, 1));
      expect(cache.isRangeFullyCached(1000, 3999), isTrue);
      expect(cache.readRangeFromCache(1500, 100)?.length, 100);
    });

    test('large range fully cached without 16MB serve cap', () {
      final cache = VideoRangeMemoryCache(
        sessionKey: 'test',
        options: const VideoRangeCacheOptions(blockSize: 4096),
      );
      cache.bindFileSize(20 * 1024 * 1024);
      final chunk = List<int>.filled(17 * 1024 * 1024, 3);
      cache.ingestBytes(0, chunk);
      expect(cache.isRangeFullyCached(0, chunk.length - 1), isTrue);
      expect(cache.cachedPrefixLength(0, chunk.length - 1), chunk.length);
    });
  });

  group('session key', () {
    test('isVideoRawFilePath', () {
      expect(isVideoRawFilePath('/api/videoPlayer/rawFile'), isTrue);
      expect(isVideoRawFilePath('/api/file/rawFile'), isTrue);
      expect(isVideoRawFilePath('/api/videoPlayer/transcode'), isFalse);
    });

    test('buildVideoRangeSessionKey excludes token', () {
      final uri = Uri.parse(
        '/api/videoPlayer/rawFile?path=/a.mp4&internalPath=x&accessToken=secret',
      );
      final key = buildVideoRangeSessionKey(uri, 'https://nas');
      expect(key, 'https://nas|/a.mp4|x');
      expect(key.contains('secret'), isFalse);
    });
  });
}
