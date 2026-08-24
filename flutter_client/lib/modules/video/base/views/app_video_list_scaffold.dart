import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/video/base/views/app_video_item_poster.dart';
import 'package:NasCabOS/modules/video/list/controller/video_list_controller.dart';
import 'package:NasCabOS/modules/video/list/view/parts/video_list_filter_menu.dart';
import 'package:NasCabOS/modules/video/list/view/parts/video_list_grid.dart';
import 'package:NasCabOS/modules/video/list/view/parts/video_list_sort_menu.dart';
import 'package:NasCabOS/modules/video/list/view/parts/video_list_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoListScaffold extends StatefulWidget {
  final String title;
  final String controllerTagSeed;
  final VideoListController Function() controllerBuilder;
  final bool enableSourceSheet;
  final VoidCallback? onBack;

  const AppVideoListScaffold({
    super.key,
    required this.title,
    required this.controllerTagSeed,
    required this.controllerBuilder,
    this.enableSourceSheet = true,
    this.onBack,
  });

  @override
  State<AppVideoListScaffold> createState() => _AppVideoListScaffoldState();
}

class _AppVideoListScaffoldState extends State<AppVideoListScaffold> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;
  final TextEditingController _searchTextCtrl = TextEditingController();
  Worker? _searchSyncWorker;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'app_video_list_${widget.controllerTagSeed}_${UniqueKey()}';
    _scrollController.addListener(_onScroll);
  }

  void _initSearchSync(VideoListController ctrl) {
    _searchSyncWorker?.dispose();
    _searchTextCtrl.text = ctrl.searchText.value;
    _searchSyncWorker = ever<String>(ctrl.searchText, (v) {
      if (!mounted) return;
      if (_searchTextCtrl.text == v) return;
      _searchTextCtrl.value = _searchTextCtrl.value.copyWith(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
        composing: TextRange.empty,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchSyncWorker?.dispose();
    _searchTextCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ctrl = Get.isRegistered<VideoListController>(tag: _controllerTag)
        ? Get.find<VideoListController>(tag: _controllerTag)
        : null;
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  void _handleBack() {
    final cb = widget.onBack;
    if (cb != null) {
      cb();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _openSourceSheet(VideoListController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Material(
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: VideoListSourcePanel(controller: controller),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSortSheet(VideoListController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final entries = getVideoListSortEntries(controller);
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final e in entries) ...[
                  if (e.divider)
                    const Divider(height: 1)
                  else
                    ListTile(
                      dense: true,
                      leading:
                          controller.sortBy.value == e.by &&
                              controller.sortOrder.value == e.order
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : const SizedBox(width: 24),
                      title: Text(e.labelKey!.tr),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        controller.setSort(e.by!, e.order!);
                      },
                    ),
                ],
              ],
            );
          }),
        );
      },
    );
  }

  Future<void> _openFilterSheet(VideoListController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final maxH = MediaQuery.of(ctx).size.height * 0.86;
        return Material(
          color: theme.colorScheme.surface,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: VideoListFilterPanel(
                    controller: controller,
                    showMediaTypeFilter: true,
                    contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconButtonOperationBar(VideoListController ctrl) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: CustomExpandableSearchBar(
              controller: _searchTextCtrl,
              hintText: 'video_list_search_hint'.tr,
              onChanged: ctrl.setSearchText,
              onClear: ctrl.clearSearch,
              defaultExpanded: true,
            ),
          ),
          const SizedBox(width: 8),
          Obx(() {
            return CustomBorderedIconButton(
              icon: Icons.sort_by_alpha,
              tooltip: 'sort'.tr,
              active: ctrl.hasCustomSort,
              onTap: () => _openSortSheet(ctrl),
            );
          }),
          const SizedBox(width: 8),
          Obx(() {
            return CustomBorderedIconButton(
              icon: Icons.filter_alt_outlined,
              tooltip: 'filter'.tr,
              active: ctrl.hasActiveFilters,
              onTap: () => _openFilterSheet(ctrl),
            );
          }),
          if (widget.enableSourceSheet) ...[
            const SizedBox(width: 8),
            Obx(() {
              return CustomBorderedIconButton(
                icon: Icons.source_outlined,
                tooltip: 'source'.tr,
                active: ctrl.selectedPaths.isNotEmpty,
                onTap: () => _openSourceSheet(ctrl),
              );
            }),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildOperationBar(VideoListController ctrl) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Obx(() {
              final labelKey = getCurrentVideoListSortLabelKey(ctrl);
              final label = (labelKey?.tr ?? 'sort'.tr).trim();
              return TextButton(
                onPressed: () => _openSortSheet(ctrl),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(label),
              );
            }),
            const Spacer(),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: VideoListSearchBar(controller: ctrl, height: 32),
            ),
            const SizedBox(width: 4),
            Obx(() {
              final active = ctrl.hasActiveFilters;
              final fg = active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface;
              return IconButton(
                tooltip: 'filter'.tr,
                onPressed: () => _openFilterSheet(ctrl),
                icon: Icon(Icons.tune, color: fg),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoListController>(
      tag: _controllerTag,
      init: widget.controllerBuilder(),
      dispose: (_) => Get.delete<VideoListController>(tag: _controllerTag),
      builder: (ctrl) {
        _initSearchSync(ctrl);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: _handleBack,
            ),
            centerTitle: true,
            titleSpacing: 0,
            title: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Column(
            children: [
              _buildIconButtonOperationBar(ctrl),
              Expanded(
                child: Obx(() {
                  if (ctrl.loading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ctrl.items.isEmpty) {
                    return CustomNoData(text: 'no_data'.tr);
                  }
                  return RefreshIndicator(
                    onRefresh: () => ctrl.refreshList(showLoading: false),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: CustomScrollView(
                        controller: _scrollController,
                        cacheExtent: 1600,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            sliver: _AppVideoListGrid(controller: ctrl),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: VideoListFooter(controller: ctrl),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppVideoListGrid extends StatelessWidget {
  final VideoListController controller;
  const _AppVideoListGrid({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final posterScale = controller.posterScale.value;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          final baseWidth = maxWidth < 420 ? 120.0 : 140.0;
          final desiredWidth = baseWidth * posterScale;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 6);
          final spacing = maxWidth < 420 ? 10.0 : 12.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
              .floorToDouble();
          final estimatedHeight = itemWidth * 1.5 + 54;
          final aspectRatio = itemWidth / estimatedHeight;

          return SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, idx) {
                final item = controller.items[idx];
                return AppVideoItemPoster(
                  item: item,
                  width: itemWidth,
                  progress: null,
                  currentAlbumId: controller.albumId,
                  onRemovedFromCurrentAlbum: () =>
                      controller.removeFromCurrentAlbumState(item.id),
                  onDeleted: (deleted) {
                    controller.items.removeWhere((e) => e.id == deleted.id);
                    controller.total.value = (controller.total.value - 1).clamp(
                      0,
                      1 << 30,
                    );
                  },
                  onFavoriteChanged: (isFav) =>
                      controller.updateFavoriteState(item.id, isFav),
                );
              },
              childCount: controller.items.length,
              addAutomaticKeepAlives: false,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
          );
        },
      );
    });
  }
}
