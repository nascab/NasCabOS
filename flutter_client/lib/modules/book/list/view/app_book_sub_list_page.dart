import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/book/list/controller/book_list_controller.dart';
import 'package:NasCabOS/modules/book/list/view/parts/book_list_grid.dart';
import 'package:NasCabOS/modules/book/book_main/view/parts/app_book_multiselect_bar.dart';

class AppBookSubListPage extends StatefulWidget {
  final int seriesId;
  final int listId;
  final int collectionId;
  final String title;
  final String type;

  const AppBookSubListPage({
    super.key,
    this.seriesId = 0,
    this.listId = 0,
    this.collectionId = 0,
    required this.title,
    this.type = 'book',
  });

  @override
  State<AppBookSubListPage> createState() => _AppBookSubListPageState();
}

class _AppBookSubListPageState extends State<AppBookSubListPage> {
  late final String _tag;
  late final BookListController _controller;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchTextCtrl = TextEditingController();
  Worker? _searchSyncWorker;

  @override
  void initState() {
    super.initState();
    if (widget.seriesId > 0) {
      _tag = 'app_book_sub_${widget.seriesId}';
    } else if (widget.listId > 0) {
      _tag = 'app_book_sub_list_${widget.listId}';
    } else if (widget.collectionId > 0) {
      _tag = 'app_book_sub_collection_${widget.collectionId}';
    } else {
      _tag = 'app_book_sub_${DateTime.now().millisecondsSinceEpoch}';
    }
    final effectiveType = widget.seriesId > 0 ? widget.type : '';
    _controller = Get.put(
      BookListController(
        type: effectiveType,
        seriesIndexId: widget.seriesId > 0 ? widget.seriesId : null,
        listId: widget.listId > 0 ? widget.listId : null,
        collectionId: widget.collectionId > 0 ? widget.collectionId : null,
      ),
      tag: _tag,
    );
    _scrollController.addListener(_onScroll);
    _initSearchSync();
  }

  void _initSearchSync() {
    _searchSyncWorker?.dispose();
    _searchTextCtrl.text = _controller.searchText.value;
    _searchSyncWorker = ever<String>(_controller.searchText, (v) {
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
    if (Get.isRegistered<BookListController>(tag: _tag)) {
      Get.delete<BookListController>(tag: _tag, force: true);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      _controller.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  Future<void> _openSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'source'.tr,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _controller.selectedPaths.clear();
                            _controller.refreshList(showLoading: false);
                          },
                          child: Text('reset'.tr),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Padding(
                  //   padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  //   child: Row(
                  //     children: [
                  //       Expanded(
                  //         child: Text(
                  //           '${'video_list_cover_size'.tr} ${(BookListController.sharedCoverScale.value * 100).round()}%',
                  //           style: theme.textTheme.bodyMedium,
                  //         ),
                  //       ),
                  //       IconButton(
                  //         tooltip: '-',
                  //         onPressed:
                  //             BookListController.sharedCoverScale.value >
                  //                 BookListController.coverScaleMin + 0.001
                  //             ? _controller.decreaseCoverScale
                  //             : null,
                  //         icon: const Icon(Icons.remove),
                  //       ),
                  //       IconButton(
                  //         tooltip: '+',
                  //         onPressed:
                  //             BookListController.sharedCoverScale.value <
                  //                 BookListController.coverScaleMax - 0.001
                  //             ? _controller.increaseCoverScale
                  //             : null,
                  //         icon: const Icon(Icons.add),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                  const Divider(height: 1),
                  if (_controller.availablePaths.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('no_path'.tr),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        itemCount: _controller.availablePaths.length,
                        itemBuilder: (ctx, index) {
                          final item = _controller.availablePaths[index];
                          final path = item.path;
                          final selected = _controller.selectedPaths.contains(
                            path,
                          );
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: (val) {
                              if (val == true) {
                                _controller.selectedPaths.add(path);
                              } else {
                                _controller.selectedPaths.remove(path);
                              }
                              _controller.refreshList(showLoading: false);
                            },
                            title: Text(path),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  List<_BookSortEntry> get _sortEntries {
    final base = <_BookSortEntry>[
      _BookSortEntry(
        by: BookListSortBy.createTime,
        order: BookListSortOrder.desc,
        labelKey: 'create_time_desc',
      ),
      _BookSortEntry(
        by: BookListSortBy.createTime,
        order: BookListSortOrder.asc,
        labelKey: 'create_time_asc',
      ),
      _BookSortEntry(
        by: BookListSortBy.name,
        order: BookListSortOrder.asc,
        labelKey: 'name_asc',
      ),
      _BookSortEntry(
        by: BookListSortBy.name,
        order: BookListSortOrder.desc,
        labelKey: 'name_desc',
      ),
    ];
    if (_controller.isFavoriteList) {
      base.addAll([
        _BookSortEntry(
          by: BookListSortBy.favoriteTime,
          order: BookListSortOrder.desc,
          labelKey: 'book_list_sort_favorite_time_desc',
        ),
        _BookSortEntry(
          by: BookListSortBy.favoriteTime,
          order: BookListSortOrder.asc,
          labelKey: 'book_list_sort_favorite_time_asc',
        ),
      ]);
    }
    return base;
  }

  String get _currentSortLabel {
    for (final e in _sortEntries) {
      if (_controller.sortBy.value == e.by &&
          _controller.sortOrder.value == e.order) {
        return e.labelKey.tr;
      }
    }
    return 'sort'.tr;
  }

  Future<void> _openSortSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final entries = _sortEntries;
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final e in entries)
                  ListTile(
                    dense: true,
                    leading:
                        _controller.sortBy.value == e.by &&
                            _controller.sortOrder.value == e.order
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox(width: 24),
                    title: Text(e.labelKey.tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _controller.setSort(e.by, e.order);
                    },
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _buildOperationBar() {
    return Obx(() {
      final disabled = _controller.isMultiSelectMode.value;
      final activeSourceCount = _controller.selectedPaths.length;
      final sourceActive = activeSourceCount > 0 && !disabled;

      return SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: CustomExpandableSearchBar(
                controller: _searchTextCtrl,
                hintText: 'book_list_search_hint'.tr,
                onChanged: _controller.setSearchText,
                onClear: _controller.clearSearch,
                defaultExpanded: true,
              ),
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.sort_by_alpha,
              tooltip: _currentSortLabel,
              active:
                  _controller.sortBy.value != BookListSortBy.createTime ||
                  _controller.sortOrder.value != BookListSortOrder.desc,
              onTap: disabled ? null : _openSortSheet,
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: sourceActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              tooltip: 'source'.tr,
              active: sourceActive,
              onTap: disabled ? null : _openSourceSheet,
            ),
            const SizedBox(width: 10),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: GetBuilder<BookListController>(
        tag: _tag,
        builder: (ctrl) {
          return Obx(() {
            final showMulti = ctrl.isMultiSelectMode.value;
            final bottomSpace = showMulti ? 86.0 : 30.0;

            if (!ctrl.firstLoaded.value &&
                ctrl.loading.value &&
                ctrl.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (ctrl.firstLoaded.value &&
                !ctrl.loading.value &&
                ctrl.items.isEmpty) {
              return Column(
                children: [
                  _buildOperationBar(),
                  Expanded(child: CustomNoData(text: 'no_data'.tr)),
                ],
              );
            }

            return Stack(
              children: [
                Column(
                  children: [
                    _buildOperationBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => ctrl.refreshList(showLoading: false),
                        child: Scrollbar(
                          controller: _scrollController,
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  0,
                                ),
                                sliver: BookListGrid(
                                  controller: ctrl,
                                  mobileLayout: true,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 6),
                              ),
                              SliverToBoxAdapter(
                                child: BookListFooter(controller: ctrl),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(height: bottomSpace),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (showMulti)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AppBookMultiSelectBottomBar(controller: ctrl),
                  ),
                if (showMulti)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: kToolbarHeight,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'cancel'.tr,
                                onPressed: ctrl.exitMultiSelectMode,
                                icon: const Icon(Icons.close),
                              ),
                              Expanded(
                                child: Text(
                                  '${ctrl.selectedItems.length} ${'selected'.tr}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          });
        },
      ),
    );
  }
}

class _BookSortEntry {
  final BookListSortBy by;
  final BookListSortOrder order;
  final String labelKey;
  const _BookSortEntry({
    required this.by,
    required this.order,
    required this.labelKey,
  });
}
