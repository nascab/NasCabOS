import 'package:NasCabOS/modules/base/components/custom_divider.dart';
import 'package:NasCabOS/modules/video/album/view/video_album_list_view.dart';
import 'package:NasCabOS/modules/video/smart_album/view/video_smart_album_list_view.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/video_main_controller.dart';
import 'home_parts/video_left_menu.dart';
import '../../source_setting/view/video_source_settings_view.dart';
import '../../home/view/video_home_page.dart';
import '../../detail/view/video_detail_page.dart';
import '../../list/view/video_list_page.dart';
import '../../history/view/video_history_page.dart';
import '../../collection/view/video_collection_list_view.dart';
import '../../other_setting/view/video_other_settings_view.dart';
import '../../../folder_view/folder_view_module_type.dart';
import '../../../folder_view/view/pc_folder_view_page.dart';

class VideoMainView extends StatelessWidget {
  const VideoMainView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoMainController>(
      init: VideoMainController(),
      builder: (ctrl) {
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;
          final detailIndexId = ctrl.activeDetailIndexId.value;
          final subDetailIndexId = ctrl.activeSubDetailIndexId.value;
          final filterOverlay = ctrl.activeFilterOverlay.value;

          return Stack(
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: leftWidth,
                    child: VideoLeftMenu(
                      controller: ctrl,
                      collapsed: collapsed,
                      onToggleCollapse: () =>
                          ctrl.sidebarCollapsed.value = !collapsed,
                    ),
                  ),
                  Expanded(child: _buildRight(ctrl)),
                ],
              ),
              if (filterOverlay != null)
                Positioned.fill(
                  child: _VideoFilterListOverlay(
                    args: filterOverlay,
                    onClose: ctrl.closeFilterOverlay,
                  ),
                ),
              if (detailIndexId != null)
                Positioned.fill(
                  child: _VideoDetailOverlay(
                    indexId: detailIndexId,
                    onClose: ctrl.closeDetail,
                  ),
                ),
              if (subDetailIndexId != null)
                Positioned.fill(
                  child: _VideoDetailOverlay(
                    indexId: subDetailIndexId,
                    onClose: ctrl.closeSubDetail,
                  ),
                ),
            ],
          );
        });
      },
    );
  }

  Widget _buildRight(VideoMainController ctrl) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        return ColoredBox(
          color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
          child: Obx(() {
            final key = ctrl.currentPageKey.value;
            if (key == 'library.home') {
              return const VideoHomePage();
            }
            if (key == 'library.tv') {
              return KeyedSubtree(
                key: const ValueKey('video_list_tv'),
                child: VideoListPage(
                  key: const ValueKey('video_list_tv_page'),
                  initialMediaType: 'tv',
                ),
              );
            }
            if (key == 'library.movie') {
              return KeyedSubtree(
                key: const ValueKey('video_list_movie'),
                child: VideoListPage(
                  key: const ValueKey('video_list_movie_page'),
                  initialMediaType: 'movie',
                ),
              );
            }
            if (key == 'library.history') {
              return const KeyedSubtree(
                key: ValueKey('video_history'),
                child: VideoHistoryPage(key: ValueKey('video_history_page')),
              );
            }
            if (key == 'library.file_view') {
              return const KeyedSubtree(
                key: ValueKey('video_folder_view'),
                child: PcFolderViewPage(moduleType: FolderViewModuleType.video),
              );
            }
            if (key == 'settings.source') {
              return const VideoSourceSettingsView();
            }
            if (key == 'albums.collection') {
              return const KeyedSubtree(
                key: ValueKey('video_collection_list'),
                child: VideoCollectionListView(
                  key: ValueKey('video_collection_list_page'),
                ),
              );
            }
            if (key == 'albums.album') {
              return const KeyedSubtree(
                key: ValueKey('video_album_list'),
                child: VideoAlbumListView(
                  key: ValueKey('video_album_list_page'),
                ),
              );
            }
            if (key == 'library.favorites') {
              return const KeyedSubtree(
                key: ValueKey('video_list_favorites'),
                child: VideoListPage(
                  key: ValueKey('video_list_favorites_page'),
                  initialMediaType: '',
                  listType: 'favorite',
                ),
              );
            }
            if (key == 'albums.smart') {
              return const KeyedSubtree(
                key: ValueKey('video_smart_album_list'),
                child: VideoSmartAlbumListView(
                  key: ValueKey('video_smart_album_list_page'),
                ),
              );
            }
            if (key == 'settings.other') {
              return const VideoOtherSettingsView();
            }
            return Center(child: Text('not_implemented_yet'.tr));
          }),
        );
      },
    );
  }
}

class _VideoDetailOverlay extends StatefulWidget {
  final int indexId;
  final VoidCallback onClose;

  const _VideoDetailOverlay({required this.indexId, required this.onClose});

  @override
  State<_VideoDetailOverlay> createState() => _VideoDetailOverlayState();
}

class _VideoDetailOverlayState extends State<_VideoDetailOverlay> {
  late final String _controllerTag;

  @override
  void initState() {
    super.initState();
    _controllerTag = 'video_detail_overlay_${widget.indexId}_${UniqueKey()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) widget.onClose();
        },
        child: KeyedSubtree(
          key: ValueKey(_controllerTag),
          child: VideoDetailPage(
            indexId: widget.indexId,
            onClose: widget.onClose,
            controllerTag: _controllerTag,
          ),
        ),
      ),
    );
  }
}

class _VideoFilterListOverlay extends StatefulWidget {
  final VideoFilterOverlayArgs args;
  final VoidCallback onClose;

  const _VideoFilterListOverlay({required this.args, required this.onClose});

  @override
  State<_VideoFilterListOverlay> createState() =>
      _VideoFilterListOverlayState();
}

class _VideoFilterListOverlayState extends State<_VideoFilterListOverlay> {
  late Key _pageKey;

  @override
  void initState() {
    super.initState();
    _pageKey = ValueKey(
      'video_filter_${widget.args.kind.name}_${widget.args.mediaType}_${widget.args.value}_${UniqueKey()}',
    );
  }

  @override
  void didUpdateWidget(covariant _VideoFilterListOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.args.kind != widget.args.kind ||
        oldWidget.args.value != widget.args.value ||
        oldWidget.args.mediaType != widget.args.mediaType) {
      _pageKey = ValueKey(
        'video_filter_${widget.args.kind.name}_${widget.args.mediaType}_${widget.args.value}_${UniqueKey()}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.args.title;
    final mediaType = widget.args.mediaType.trim();

    List<String> resolveGenres() {
      if (widget.args.kind != VideoFilterOverlayKind.genre) return const [];
      return <String>[widget.args.value];
    }

    List<String> resolveRegions() {
      if (widget.args.kind != VideoFilterOverlayKind.region) return const [];
      return <String>[widget.args.value];
    }

    List<String> resolveActors() {
      if (widget.args.kind != VideoFilterOverlayKind.actor) return const [];
      return <String>[widget.args.value];
    }

    List<String> resolveDirectors() {
      if (widget.args.kind != VideoFilterOverlayKind.director) return const [];
      return <String>[widget.args.value];
    }

    return Material(
      color: theme.colorScheme.surface,
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) widget.onClose();
        },
        child: Column(
          children: [
            SizedBox(height: 25),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close),
                    tooltip: 'close'.tr,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            CustomDivider(),
            Expanded(
              child: KeyedSubtree(
                key: _pageKey,
                child: VideoListPage(
                  initialMediaType: mediaType,
                  showTopSpacer: false,
                  initialGenres: resolveGenres(),
                  initialRegions: resolveRegions(),
                  initialActors: resolveActors(),
                  initialDirectors: resolveDirectors(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
