import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_popup_select_button.dart';
import '../../controller/video_list_controller.dart';
import 'video_list_filter_menu.dart';
import 'video_list_sort_menu.dart';
import '../../../../../utils/popup_menu_util.dart';

class VideoListSourcePanel extends StatelessWidget {
  final VideoListController controller;
  final bool showHeader;
  final BoxConstraints listConstraints;
  const VideoListSourcePanel({
    super.key,
    required this.controller,
    this.showHeader = true,
    this.listConstraints = const BoxConstraints(maxHeight: 150),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('source'.tr, style: Get.textTheme.titleSmall),
                TextButton(
                  onPressed: () {
                    controller.clearSourcePathSelection(showLoading: false);
                  },
                  child: Text('reset'.tr),
                ),
              ],
            ),
          ),
        if (showHeader) const Divider(height: 1),
        ConstrainedBox(
          constraints: listConstraints,
          child: Obx(() {
            if (controller.availablePaths.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text('no_path'.tr),
              );
            }
            return ListView.builder(
              itemCount: controller.availablePaths.length,
              itemBuilder: (ctx, index) {
                final item = controller.availablePaths[index];
                final path = item.path;
                return Obx(() {
                  final isSelected = controller.selectedPaths.contains(path);
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(path, style: Get.textTheme.bodySmall),
                        ),
                        if (item.valid)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          )
                        else
                          const Icon(Icons.cancel, color: Colors.red, size: 16),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (val) {
                      controller.setSourcePathSelected(
                        path,
                        val == true,
                        showLoading: false,
                      );
                    },
                  );
                });
              },
            );
          }),
        ),
      ],
    );
  }
}

class VideoListTopBar extends StatefulWidget {
  final VideoListController controller;
  const VideoListTopBar({super.key, required this.controller});

  @override
  State<VideoListTopBar> createState() => _VideoListTopBarState();
}

class _VideoListTopBarState extends State<VideoListTopBar> {
  final _sourceKey = GlobalKey();
  final _filterKey = GlobalKey();
  final _sortKey = GlobalKey();

  VideoListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.initialMediaType.trim().isEmpty) ...[
                      Obx(() {
                        return CustomPopupSelectButton<String>(
                          icon: Icons.video_library_outlined,
                          tooltip: 'type'.tr,
                          value: controller.mediaType.value,
                          defaultValue: '',
                          items: [
                            CustomPopupSelectItem(
                              value: '',
                              label: 'all'.tr,
                              icon: Icons.video_library_outlined,
                            ),
                            CustomPopupSelectItem(
                              value: 'movie',
                              label: 'video_home_type_movie'.tr,
                              icon: Icons.movie_outlined,
                            ),
                            CustomPopupSelectItem(
                              value: 'tv',
                              label: 'video_home_type_tv'.tr,
                              icon: Icons.live_tv_outlined,
                            ),
                          ],
                          onSelected: controller.setMediaType,
                        );
                      }),
                      const SizedBox(width: 8),
                    ],
                    // 来源筛选
                    Obx(() {
                      final count = controller.selectedPaths.length;
                      return CustomBorderedIconButton(
                        key: _sourceKey,
                        icon: Icons.source_outlined,
                        tooltip: 'source'.tr,
                        active: count > 0,
                        onTap: () {
                          PopupMenuUtil.showBelowButton<void>(
                            context: context,
                            buttonKey: _sourceKey,
                            items: [
                              PopupMenuItem(
                                enabled: false,
                                padding: EdgeInsets.zero,
                                child: SizedBox(
                                  width: 350,
                                  child: VideoListSourcePanel(
                                    controller: controller,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    // 筛选
                    Obx(() {
                      final count = controller.activeFilterCount;
                      return CustomBorderedIconButton(
                        key: _filterKey,
                        icon: Icons.filter_alt_outlined,
                        tooltip: 'filter'.tr,
                        active: count > 0,
                        onTap: () {
                          PopupMenuUtil.showBelowButton<void>(
                            context: context,
                            buttonKey: _filterKey,
                            items: [
                              PopupMenuItem(
                                enabled: false,
                                padding: EdgeInsets.zero,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 860,
                                    minWidth: 560,
                                  ),
                                  child: VideoListFilterPanel(
                                    controller: controller,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    // 排序
                    Obx(() {
                      final by = controller.sortBy.value;
                      final order = controller.sortOrder.value;
                      final isFavorite = controller.isFavoriteList;
                      final defaultBy = isFavorite
                          ? VideoListSortBy.favoriteTime
                          : VideoListSortBy.viewTime;
                      final isActive =
                          by != defaultBy || order != VideoListSortOrder.desc;
                      return CustomBorderedIconButton(
                        key: _sortKey,
                        icon: Icons.sort_by_alpha,
                        tooltip: 'sort'.tr,
                        active: isActive,
                        onTap: () async {
                          final result =
                              await PopupMenuUtil.showBelowButton<
                                (VideoListSortBy, VideoListSortOrder)
                              >(
                                context: context,
                                buttonKey: _sortKey,
                                items: _buildSortMenuItems(controller),
                              );
                          if (result != null) {
                            controller.setSort(result.$1, result.$2);
                          }
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    // 封面缩放
                    Obx(() {
                      final scale = controller.posterScale.value;
                      final canDecrease =
                          scale > VideoListController.posterScaleMin + 0.001;
                      final canIncrease =
                          scale < VideoListController.posterScaleMax - 0.001;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomBorderedIconButton(
                            icon: Icons.zoom_out,
                            tooltip: 'zoom_out'.tr,
                            enabled: canDecrease,
                            onTap: controller.decreasePosterScale,
                          ),
                          const SizedBox(width: 4),
                          CustomBorderedIconButton(
                            icon: Icons.zoom_in,
                            tooltip: 'zoom_in'.tr,
                            enabled: canIncrease,
                            onTap: controller.increasePosterScale,
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            VideoListSearchBar(controller: controller),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<(VideoListSortBy, VideoListSortOrder)>>
  _buildSortMenuItems(VideoListController controller) {
    final currentBy = controller.sortBy.value;
    final currentOrder = controller.sortOrder.value;
    return getVideoListSortEntries(controller).map((e) {
      if (e.divider) {
        return const PopupMenuItem<(VideoListSortBy, VideoListSortOrder)>(
          enabled: false,
          height: 1,
          padding: EdgeInsets.zero,
          child: Divider(height: 1),
        );
      }
      final selected = e.by == currentBy && e.order == currentOrder;
      return PopupMenuItem<(VideoListSortBy, VideoListSortOrder)>(
        value: (e.by!, e.order!),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: selected ? const Icon(Icons.check, size: 18) : null,
            ),
            Icon(_sortByIcon(e.by!), size: 18),
            const SizedBox(width: 8),
            Text(e.labelKey!.tr),
          ],
        ),
      );
    }).toList();
  }

  IconData _sortByIcon(VideoListSortBy by) {
    switch (by) {
      case VideoListSortBy.favoriteTime:
        return Icons.favorite_border;
      case VideoListSortBy.viewTime:
        return Icons.visibility_outlined;
      case VideoListSortBy.createTime:
        return Icons.schedule;
      case VideoListSortBy.year:
        return Icons.calendar_today_outlined;
      case VideoListSortBy.score:
        return Icons.star_border;
      case VideoListSortBy.name:
        return Icons.sort_by_alpha;
    }
  }
}

class VideoListSearchBar extends StatefulWidget {
  final VideoListController controller;
  final double height;
  const VideoListSearchBar({
    super.key,
    required this.controller,
    this.height = 32,
  });

  @override
  State<VideoListSearchBar> createState() => _VideoListSearchBarState();
}

class _VideoListSearchBarState extends State<VideoListSearchBar> {
  late final TextEditingController _ctrl;
  late final Worker _syncWorker;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.controller.searchText.value);
    _syncWorker = ever<String>(widget.controller.searchText, (v) {
      if (!mounted) return;
      if (_ctrl.text == v) return;
      _ctrl.value = _ctrl.value.copyWith(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
        composing: TextRange.empty,
      );
    });
  }

  @override
  void dispose() {
    _syncWorker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomExpandableSearchBar(
      controller: _ctrl,
      hintText: 'video_list_search_hint'.tr,
      onChanged: widget.controller.setSearchText,
      onClear: widget.controller.clearSearch,
      height: widget.height,
    );
  }
}
