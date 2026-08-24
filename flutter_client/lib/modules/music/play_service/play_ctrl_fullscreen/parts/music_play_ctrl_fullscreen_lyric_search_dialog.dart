import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../core/api/base_api_service.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/format_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../controller/music_play_service_controller.dart';

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

  Duration get duration =>
      Duration(milliseconds: durationMs < 0 ? 0 : durationMs);

  String get previewLine {
    return _firstLyricLineFromLrc(lrc);
  }

  static String _firstLyricLineFromLrc(String lrc) {
    final text = lrc.trim();
    if (text.isEmpty) return '';
    final lines = text.split(RegExp(r'\r?\n'));
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.contains(']')) {
        final idx = line.lastIndexOf(']');
        final after = idx >= 0 ? line.substring(idx + 1).trim() : '';
        if (after.isNotEmpty) return after;
        continue;
      }
      return line;
    }
    return '';
  }
}

class _LyricApiService extends BaseApiService {
  static _LyricApiService get instance => _LyricApiService();

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

class MusicPlayCtrlFullScreenLyricSearchDialog {
  static String _fileStem(String filePath) {
    final raw = filePath.trim();
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final dot = name.lastIndexOf('.');
    if (dot > 0) return name.substring(0, dot);
    return name;
  }

  static String _normalizeForContains(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'[^0-9a-z\u4e00-\u9fff]+'), '');
  }

  static Future<String?> show(
    BuildContext context, {
    required String musicPath,
    required String title,
    required String artist,
    required Duration trackDuration,
  }) async {
    final theme = Theme.of(context);
    var keyword = '$title $artist'.trim();
    var loading = false;
    var selectingId = '';
    var results = <_LyricSearchItem>[];
    var didAutoSearch = false;

    Future<void> doSearch(StateSetter setState) async {
      final q = keyword.trim();
      if (q.isEmpty) {
        ToastUtil.show('input_please'.tr);
        return;
      }
      setState(() {
        loading = true;
        results = <_LyricSearchItem>[];
      });
      try {
        final list = await _LyricApiService.instance.searchLyric(q);
        setState(() {
          results = list;
        });
      } finally {
        setState(() {
          loading = false;
        });
      }
    }

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!didAutoSearch) {
              didAutoSearch = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) doSearch(setState);
              });
            }
            final input = TextFormField(
              initialValue: keyword,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'search'.tr,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: loading ? null : () => doSearch(setState),
                  icon: const Icon(Icons.search),
                  tooltip: 'search'.tr,
                ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (v) => keyword = v,
              onFieldSubmitted: (_) => doSearch(setState),
            );

            Widget body;
            if (loading) {
              body = const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            } else if (results.isEmpty) {
              body = Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Center(child: Text('no_data'.tr)),
              );
            } else {
              body = ListView.separated(
                itemCount: results.length,
                separatorBuilder: (context, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = results[index];
                  final durationDiffMs =
                      (item.durationMs - trackDuration.inMilliseconds).abs();
                  final durationMatch =
                      item.durationMs > 0 && durationDiffMs <= 5000;
                  final fileStemNorm = _normalizeForContains(
                    _fileStem(musicPath),
                  );
                  final titleNorm = _normalizeForContains(item.title);
                  final nameMatch =
                      titleNorm.isNotEmpty &&
                      fileStemNorm.isNotEmpty &&
                      fileStemNorm.contains(titleNorm);
                  final highMatch = durationMatch && nameMatch;
                  final meta = [
                    if (item.artist.trim().isNotEmpty) item.artist.trim(),
                    if (item.album.trim().isNotEmpty) item.album.trim(),
                    if (item.durationMs > 0)
                      FormatUtil.formatDuration(item.duration),
                  ].join(' · ');

                  final selecting = selectingId == item.id;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (highMatch)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '高匹配度',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: 11,
                                              height: 1.2,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.85),
                                            ),
                                      ),
                                    ),
                                  if (highMatch) const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.title.trim().isEmpty
                                          ? item.id
                                          : item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              if (meta.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Tooltip(
                                  message: item.lrc.trim(),
                                  waitDuration: const Duration(
                                    milliseconds: 250,
                                  ),
                                  child: Text(
                                    item.previewLine.trim().isEmpty
                                        ? '\u00A0'
                                        : item.previewLine.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 90,
                          child: TextButton(
                            onPressed: selecting
                                ? null
                                : () async {
                                    final lrc = item.lrc.trim();
                                    if (lrc.isEmpty) {
                                      ToastUtil.show('operation_failed'.tr);
                                      return;
                                    }
                                    setState(() {
                                      selectingId = item.id;
                                    });
                                    try {
                                      final ok = await _LyricApiService.instance
                                          .setLyric(
                                            musicPath: musicPath,
                                            lrc: lrc,
                                          );
                                      if (!ok) {
                                        ToastUtil.show('operation_failed'.tr);
                                        return;
                                      }
                                      MusicPlayServiceController.instance
                                          .applyLyricOverride(musicPath, lrc);
                                      if (ctx.mounted) {
                                        Navigator.of(ctx).pop(lrc);
                                      }
                                      ToastUtil.show('operation_success'.tr);
                                    } finally {
                                      if (context.mounted) {
                                        setState(() {
                                          selectingId = '';
                                        });
                                      }
                                    }
                                  },
                            child: selecting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text('select'.tr),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            return DialogUtil.createAlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text('music_search_lyric'.tr)),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxWidth: 780, minWidth: 540),
              content: SizedBox(
                width: 740,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    input,
                    const SizedBox(height: 8),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
