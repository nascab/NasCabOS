import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../core/api/api_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../controller/video_detail_controller.dart';
import '../../service/video_detail_api_service.dart';
import '../../../base/video_utils/video_utils.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/toast_util.dart';

/// 剧集区：排序 + 视图切换 + 列表（简介/文件）。
class VideoDetailEpisodeSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailEpisodeSection({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EpisodeHeader(ctrl: ctrl),
        const SizedBox(height: 10),
        _EpisodePager(ctrl: ctrl),
        const SizedBox(height: 10),
        _EpisodeList(ctrl: ctrl),
      ],
    );
  }
}

class _EpisodeHeader extends StatelessWidget {
  final VideoDetailController ctrl;

  const _EpisodeHeader({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Obx(() {
          final total = ctrl.episodeTotal.value;
          final suffix = total > 0 ? ' ($total)' : '';
          return Text(
            '${'video_detail_episodes'.tr}$suffix',
            style: theme.textTheme.titleMedium,
          );
        }),
        const Spacer(),
        Obx(() {
          final asc = ctrl.episodeAsc.value;
          return IconButton(
            onPressed: ctrl.toggleEpisodeSort,
            tooltip: asc
                ? 'video_detail_sort_asc'.tr
                : 'video_detail_sort_desc'.tr,
            icon: Icon(asc ? Icons.north : Icons.south),
          );
        }),
        const SizedBox(width: 6),
        Obx(() {
          final mode = ctrl.episodeViewMode.value;
          return ToggleButtons(
            isSelected: [
              mode == EpisodeViewMode.intro,
              mode == EpisodeViewMode.file,
            ],
            onPressed: (idx) {
              ctrl.episodeViewMode.value = idx == 0
                  ? EpisodeViewMode.intro
                  : EpisodeViewMode.file;
            },
            borderRadius: BorderRadius.circular(10),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('video_detail_view_intro'.tr),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('file'.tr),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _EpisodePager extends StatelessWidget {
  final VideoDetailController ctrl;

  const _EpisodePager({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final loading = ctrl.episodeLoading.value;
      final totalPages = ctrl.episodeTotalPages;
      final total = ctrl.episodeTotal.value;
      final current = ctrl.episodePage.value;
      final asc = ctrl.episodeAsc.value;

      if (loading) {
        return SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }

      if (totalPages <= 1) return const SizedBox.shrink();

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...List.generate(totalPages, (i) {
            final page = i + 1;
            final size = ctrl.episodePageSize;
            final start = asc
                ? (page - 1) * size + 1
                : (total - page * size + 1).clamp(1, total);
            final end = asc
                ? (page * size).clamp(1, total)
                : (total - (page - 1) * size).clamp(1, total);
            final selected = page == current;
            final label = '$start-$end';

            return InkWell(
              onTap: () => ctrl.jumpToEpisodePage(page),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }),
        ],
      );
    });
  }
}

class _EpisodeList extends StatelessWidget {
  final VideoDetailController ctrl;

  const _EpisodeList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = ctrl.episodeViewMode.value;
      final items = ctrl.episodeList;
      if (ctrl.episodeLoading.value && items.isEmpty) {
        return const SizedBox(height: 120);
      }
      if (items.isEmpty) return const SizedBox.shrink();
      if (mode == EpisodeViewMode.file) {
        return _EpisodeFileList(ctrl: ctrl, items: items);
      }
      return _EpisodeIntroList(ctrl: ctrl, items: items);
    });
  }
}

class _EpisodeIntroList extends StatelessWidget {
  final VideoDetailController ctrl;
  final List<Map<String, dynamic>> items;

  const _EpisodeIntroList({required this.ctrl, required this.items});

  bool get _isShowingAllEpisodes {
    final total = ctrl.episodeTotal.value;
    if (total <= 0) return false;
    return items.length >= total;
  }

  String _pickEpisodeName(Map<String, dynamic> e) {
    final nfo = (e['nfo_name']?.toString() ?? '').trim();
    if (nfo.isNotEmpty) return nfo;
    return e['filename']?.toString() ?? '';
  }

  String _pickEpisodePath(Map<String, dynamic> e) {
    return (e['full_path']?.toString() ?? '').trim();
  }

  Future<void> _playEpisodeAt(BuildContext context, int index) async {
    if (index < 0 || index >= items.length) return;
    final clicked = items[index];
    final clickedPath = _pickEpisodePath(clicked);
    if (clickedPath.isEmpty) return;

    if (_isShowingAllEpisodes) {
      final playlist = items
          .map(
            (e) => {'path': _pickEpisodePath(e), 'name': _pickEpisodeName(e)},
          )
          .where((e) => (e['path']?.toString() ?? '').trim().isNotEmpty)
          .toList();
      if (playlist.isEmpty) return;

      final initialIndex = playlist.indexWhere(
        (p) => (p['path']?.toString() ?? '') == clickedPath,
      );
      AppRoutes.toVideoPlayer(
        playlist: playlist,
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
        ignoreFindSub: 0,
      );
      return;
    }

    final res = await VideoDetailApiService.instance.getTvPlayInfo(
      ctrl.indexId,
      showLoading: true,
    );
    if (!res.success || res.data == null) {
      ToastUtil.show(res.message ?? 'video_detail_load_failed'.tr);
      return;
    }

    final data = res.data!;
    final rawList = data['playlist'];
    final list = rawList is List ? rawList : const [];
    var playlist = list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (playlist.isEmpty) {
      ToastUtil.show(res.message ?? 'video_detail_load_failed'.tr);
      return;
    }

    if (!ctrl.episodeAsc.value) {
      playlist = playlist.reversed.toList(growable: false);
    }

    final initialIndex = playlist.indexWhere(
      (p) => (p['path']?.toString() ?? '') == clickedPath,
    );
    AppRoutes.toVideoPlayer(
      playlist: playlist,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
      ignoreFindSub: 0,
    );
  }

  void _showEpisodeIntroDialog(BuildContext context, Map<String, dynamic> e) {
    final theme = Theme.of(context);
    final title = _pickEpisodeName(e);
    final fp = _pickEpisodePath(e);
    final plot = (e['nfo_storyline']?.toString() ?? '').trim();
    final epNum = (e['episod_num'] as num?)?.toInt() ?? 0;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return DialogUtil.createAlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  epNum > 0
                      ? 'video_detail_episode_no'.trParams({
                          'num': epNum.toString(),
                        })
                      : 'video_detail_episodes'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
                splashRadius: 18,
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  if (fp.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.75,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            fp,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.subject,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.75,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          plot.isNotEmpty
                              ? plot
                              : 'video_detail_storyline_empty'.tr,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const baseWidth = 320.0;
    const spacing = 10.0;
    const cardHeight = 95.0;
    const imageWidth = 115.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.clamp(0, 99999);
        final crossAxisCount =
            (((availableWidth + spacing) / (baseWidth + spacing)).floor())
                .clamp(1, 99);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final e = items[i];
            final epNum = (e['episod_num'] as num?)?.toInt() ?? 0;
            final title = (e['nfo_name']?.toString().trim().isNotEmpty ?? false)
                ? e['nfo_name'].toString()
                : (e['filename']?.toString() ?? '');
            final plot = (e['nfo_storyline']?.toString() ?? '').trim();
            final imgUrl = VideoUtils.getPosterUrl(
              VideoHomeItemBean.fromJson(Map<String, dynamic>.from(e as Map)),
              size: 300,
            );
            final borderColor = theme.colorScheme.onSurface.withValues(
              alpha: 0.30,
            );
            final canPlay = _pickEpisodePath(e).isNotEmpty;

            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canPlay ? () => _playEpisodeAt(context, i) : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: imageWidth,
                        height: cardHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor, width: 1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CustomExtendedImage(
                                  imageUrl: imgUrl,
                                  fit: BoxFit.cover,
                                  showLoading: false,
                                  borderRadius: 0,
                                ),
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: _PlayBadge(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (epNum > 0)
                                Text(
                                  'video_detail_episode_no'.trParams({
                                    'num': epNum.toString(),
                                  }),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (epNum > 0) const SizedBox(height: 2),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () =>
                                      _showEpisodeIntroDialog(context, e),
                                  child: Text(
                                    plot.isNotEmpty
                                        ? plot
                                        : 'video_detail_storyline_empty'.tr,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EpisodeFileList extends StatelessWidget {
  final VideoDetailController ctrl;
  final List<Map<String, dynamic>> items;

  const _EpisodeFileList({required this.ctrl, required this.items});

  bool get _isShowingAllEpisodes {
    final total = ctrl.episodeTotal.value;
    if (total <= 0) return false;
    return items.length >= total;
  }

  String _pickEpisodeName(Map<String, dynamic> e) {
    final nfo = (e['nfo_name']?.toString() ?? '').trim();
    if (nfo.isNotEmpty) return nfo;
    return e['filename']?.toString() ?? '';
  }

  String _pickEpisodePath(Map<String, dynamic> e) {
    return (e['full_path']?.toString() ?? '').trim();
  }

  Future<void> _playEpisodeAt(BuildContext context, int index) async {
    if (index < 0 || index >= items.length) return;
    final clicked = items[index];
    final clickedPath = _pickEpisodePath(clicked);
    if (clickedPath.isEmpty) return;

    if (_isShowingAllEpisodes) {
      final playlist = items
          .map(
            (e) => {'path': _pickEpisodePath(e), 'name': _pickEpisodeName(e)},
          )
          .where((e) => (e['path']?.toString() ?? '').trim().isNotEmpty)
          .toList();
      if (playlist.isEmpty) return;

      final initialIndex = playlist.indexWhere(
        (p) => (p['path']?.toString() ?? '') == clickedPath,
      );
      AppRoutes.toVideoPlayer(
        playlist: playlist,
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
        ignoreFindSub: 0,
      );
      return;
    }

    final res = await VideoDetailApiService.instance.getTvPlayInfo(
      ctrl.indexId,
      showLoading: true,
    );
    if (!res.success || res.data == null) {
      ToastUtil.show(res.message ?? 'video_detail_load_failed'.tr);
      return;
    }

    final data = res.data!;
    final rawList = data['playlist'];
    final list = rawList is List ? rawList : const [];
    var playlist = list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (playlist.isEmpty) {
      ToastUtil.show(res.message ?? 'video_detail_load_failed'.tr);
      return;
    }

    if (!ctrl.episodeAsc.value) {
      playlist = playlist.reversed.toList(growable: false);
    }

    final initialIndex = playlist.indexWhere(
      (p) => (p['path']?.toString() ?? '') == clickedPath,
    );
    AppRoutes.toVideoPlayer(
      playlist: playlist,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
      ignoreFindSub: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const baseWidth = 320.0;
    const spacing = 10.0;
    const cardHeight = 95.0;
    const imageWidth = 115.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.clamp(0, 99999);
        final crossAxisCount =
            (((availableWidth + spacing) / (baseWidth + spacing)).floor())
                .clamp(1, 99);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final e = items[i];
            final title = e['filename']?.toString() ?? '';
            final epNum = (e['episod_num'] as num?)?.toInt() ?? 0;
            final fp = (e['full_path']?.toString() ?? '').trim();
            final thumb = fp.isNotEmpty
                ? ApiController.instance.getTinyUrl(fp)
                : '';
            final borderColor = theme.colorScheme.onSurface.withValues(
              alpha: 0.30,
            );
            final canPlay = fp.isNotEmpty;

            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canPlay ? () => _playEpisodeAt(context, i) : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: imageWidth,
                        height: cardHeight,
                        child: thumb.isNotEmpty
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: borderColor,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CustomExtendedImage(
                                        imageUrl: thumb,
                                        fit: BoxFit.cover,
                                        showLoading: false,
                                        borderRadius: 0,
                                      ),
                                      const Positioned(
                                        top: 6,
                                        right: 6,
                                        child: _PlayBadge(),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(color: theme.colorScheme.surface),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (epNum > 0)
                                Text(
                                  'video_detail_episode_no'.trParams({
                                    'num': epNum.toString(),
                                  }),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (epNum > 0) const SizedBox(height: 2),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                fp,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(
          Icons.play_arrow_rounded,
          size: 14,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
