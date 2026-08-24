part of '../music_play_service_controller.dart';

extension MusicPlayServiceLyrics on MusicPlayServiceController {
  void applyLyricOverride(String musicPath, String lyricText) {
    final p = musicPath.trim();
    if (p.isEmpty) return;
    final next = lyricText.trim();
    _lyricsCache[p] = next;

    final idx = currentIndex.value;
    if (idx < 0 || idx >= playlist.length) return;
    final currentPath = _resolvePlayablePath(playlist[idx]).trim();
    if (currentPath == p) {
      currentLyrics.value = next;
    }
  }

  Future<void> _maybeAutoSetLyricForCurrent() async {
    if (playlist.isEmpty) return;
    final idx = currentIndex.value;
    if (idx < 0 || idx >= playlist.length) return;
    final filePath = _resolvePlayablePath(playlist[idx]).trim();
    if (filePath.isEmpty) return;
    if ((_lyricsCache[filePath] ?? '').trim().isNotEmpty) return;
    if (duration.value.inMilliseconds <= 0) return;
    unawaited(
      _tryAutoSetLyricIfNoLyric(filePath: filePath, item: playlist[idx]),
    );
  }

  Future<void> _refreshDetailForIndex(int index) async {
    if (index < 0 || index >= playlist.length) return;
    final existing = playlist[index];
    final filePath = _resolvePlayablePath(existing).trim();
    if (filePath.isEmpty) {
      if (index == currentIndex.value) currentLyrics.value = '';
      return;
    }

    final indexId = (!existing.isSeries && existing.id > 0)
        ? existing.id
        : null;
    unawaited(
      MusicListApiService.instance.refreshHistory(
        indexId: indexId,
        filePath: filePath,
        showLoading: false,
      ),
    );

    final cachedDetail = _detailCache[filePath];
    final cachedLyrics = _lyricsCache[filePath];
    if (cachedDetail != null || cachedLyrics != null) {
      if (cachedDetail != null) {
        final fromFile =
            existing.isFromFile ||
            existing.showType.trim().toLowerCase() == 'file_browser';
        final merged = fromFile
            ? cachedDetail.copyWith(
                isFavorite: existing.isFavorite,
                id: 0,
                showType: existing.showType,
                isFromFile: true,
              )
            : cachedDetail.copyWith(
                isFavorite: existing.isFavorite,
                isFromFile: existing.isFromFile,
              );
        if (playlist[index] != merged) {
          playlist[index] = merged;
          _syncMediaItem(index);
        }
      }
      if (index == currentIndex.value) {
        final lyricText = (cachedLyrics ?? '').trim();
        currentLyrics.value = lyricText;
        if (lyricText.isEmpty) {
          final target = playlist[index];
          unawaited(
            _tryAutoSetLyricIfNoLyric(filePath: filePath, item: target),
          );
        }
      }
      return;
    }

    final token = ++_detailFetchToken;
    final res = await MusicListApiService.instance.getDetailByPath(
      filePath,
      showLoading: false,
    );
    if (token != _detailFetchToken) return;
    if (!res.success) {
      if (index == currentIndex.value) currentLyrics.value = '';
      return;
    }

    final data = res.data ?? const <String, dynamic>{};
    final itemRaw = data['item'];
    final lyrics = (data['lyrics']?.toString() ?? '').trim();

    if (itemRaw is Map) {
      final detail = MusicListItem.fromJson(itemRaw.cast<String, dynamic>());
      final fromFile =
          existing.isFromFile ||
          existing.showType.trim().toLowerCase() == 'file_browser';
      final merged = fromFile
          ? detail.copyWith(
              isFavorite: existing.isFavorite,
              id: 0,
              showType: existing.showType,
              isFromFile: true,
            )
          : detail.copyWith(
              isFavorite: existing.isFavorite,
              isFromFile: existing.isFromFile,
            );
      playlist[index] = merged;
      _detailCache[filePath] = merged;
      _syncMediaItem(index);
    }

    _lyricsCache[filePath] = lyrics;
    if (index == currentIndex.value) currentLyrics.value = lyrics;
    if (index == currentIndex.value && lyrics.isEmpty) {
      final target = playlist[index];
      unawaited(_tryAutoSetLyricIfNoLyric(filePath: filePath, item: target));
    }
  }

  Future<void> _tryAutoSetLyricIfNoLyric({
    required String filePath,
    required MusicListItem item,
  }) async {
    final p = filePath.trim();
    if (p.isEmpty) return;
    if (_autoLyricTried.contains(p)) return;

    final cached = (_lyricsCache[p] ?? '').trim();
    if (cached.isNotEmpty) return;

    final expectedMsFromPlayer = duration.value.inMilliseconds;
    final expectedMs = expectedMsFromPlayer > 0
        ? expectedMsFromPlayer
        : _musicDurationSecondsToMs(item.duration);
    if (expectedMs <= 0) return;

    final keyword = _buildLyricSearchKeyword(item, filePath: p);
    if (keyword.isEmpty) return;

    _autoLyricTried.add(p);

    final results = await _LyricApiService.instance.searchLyric(
      keyword,
      showLoading: false,
    );
    if (results.isEmpty) return;
    final stemNorm = _normalizeForContains(_fileStem(p));
    final matched = results.where((it) {
      return _isHighMatch(
        candidate: it,
        fileStemNormalized: stemNorm,
        expectedDurationMs: expectedMs,
      );
    }).toList();
    if (matched.isEmpty) return;

    final chosen = matched.first;
    final lrc = chosen.lrc.trim();
    if (lrc.isEmpty) return;

    final ok = await _LyricApiService.instance.setLyric(
      musicPath: p,
      lrc: lrc,
      showLoading: false,
    );
    if (!ok) return;
    applyLyricOverride(p, lrc);
  }

  String _buildLyricSearchKeyword(
    MusicListItem item, {
    required String filePath,
  }) {
    final rawTitle = item.title.trim();
    final rawArtist = item.artist.trim();
    final fallbackTitle = _fileStem(
      item.filename.trim().isNotEmpty ? item.filename : filePath,
    );
    final title = (rawTitle.isNotEmpty ? rawTitle : fallbackTitle).trim();
    if (title.isEmpty) return '';
    if (rawArtist.isNotEmpty) return '$title $rawArtist';
    return title;
  }

  /// [MusicListItem.duration] 为秒，与数据库一致。
  int _musicDurationSecondsToMs(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    if (s <= 0) return 0;
    return s * 1000;
  }

  bool _isHighMatch({
    required _LyricSearchItem candidate,
    required String fileStemNormalized,
    required int expectedDurationMs,
  }) {
    final titleNorm = _normalizeForContains(candidate.title);
    if (titleNorm.isEmpty) return false;
    final durationMatch =
        candidate.durationMs > 0 &&
        (candidate.durationMs - expectedDurationMs).abs() <= 5000;
    final nameMatch =
        titleNorm.isNotEmpty &&
        fileStemNormalized.isNotEmpty &&
        fileStemNormalized.contains(titleNorm);

    return durationMatch && nameMatch;
  }

  String _fileStem(String pathOrFile) {
    final input = pathOrFile.trim();
    if (input.isEmpty) return '';
    final slash = input.lastIndexOf('/');
    final backSlash = input.lastIndexOf('\\');
    final sep = slash > backSlash ? slash : backSlash;
    final name = sep >= 0 ? input.substring(sep + 1) : input;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  String _normalizeForContains(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');
  }
}

class _LyricSearchItem {
  final String id;
  final String source;
  final String title;
  final String album;
  final String artist;
  final int durationMs;
  final String preview;
  final String lrc;

  const _LyricSearchItem({
    required this.id,
    required this.source,
    required this.title,
    required this.album,
    required this.artist,
    required this.durationMs,
    required this.preview,
    required this.lrc,
  });

  factory _LyricSearchItem.fromMap(Map<dynamic, dynamic> map) {
    return _LyricSearchItem(
      id: map['id']?.toString() ?? '',
      source: map['source']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      album: map['album']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      durationMs: int.tryParse(map['duration']?.toString() ?? '') ?? 0,
      preview: map['preview']?.toString() ?? '',
      lrc: map['lrc']?.toString() ?? '',
    );
  }
}

class _LyricApiService extends BaseApiService {
  static final _LyricApiService instance = _LyricApiService._();
  _LyricApiService._();

  Future<List<_LyricSearchItem>> searchLyric(
    String keyword, {
    bool showLoading = false,
  }) async {
    final q = keyword.trim();
    if (q.isEmpty) return const <_LyricSearchItem>[];
    final res = await apiPost<List<dynamic>>(
      '/api/music/lyric/search',
      body: {'keyword': q},
      showLoading: showLoading,
    );
    if (!res.success) return const <_LyricSearchItem>[];
    final raw = res.data ?? const <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => _LyricSearchItem.fromMap(e))
        .toList();
  }

  Future<bool> setLyric({
    required String musicPath,
    required String lrc,
    bool showLoading = false,
  }) async {
    final p = musicPath.trim();
    final lyric = lrc.trim();
    if (p.isEmpty || lyric.isEmpty) return false;
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/lyric/set',
      body: {'music_path': p, 'lrc': lyric},
      showLoading: showLoading,
    );
    return res.success;
  }
}
