import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/book/book_main/view/parts/app_book_custom_list_view.dart';
import 'package:NasCabOS/modules/book/book_main/view/parts/app_book_collection_view.dart';
import 'package:NasCabOS/modules/book/cache_download/view/book_cache_download_view.dart';
import 'package:NasCabOS/modules/folder_view/folder_view_module_type.dart';
import 'package:NasCabOS/modules/folder_view/view/app_folder_view_page.dart';
import 'package:NasCabOS/modules/book/history/controller/book_history_controller.dart';
import 'package:NasCabOS/modules/book/history/view/book_history_list_view.dart';
import 'package:NasCabOS/modules/book/list/controller/book_list_controller.dart';
import 'package:NasCabOS/modules/book/list/view/parts/book_list_grid.dart';
import 'package:NasCabOS/modules/book/source_setting/view/book_source_settings_view.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'parts/app_book_multiselect_bar.dart';

class AppBookMainView extends StatefulWidget {
  const AppBookMainView({super.key});

  @override
  State<AppBookMainView> createState() => _AppBookMainViewState();
}

class _AppBookMainViewState extends State<AppBookMainView> {
  int _tabIndex = 0;
  int _libraryIndex = 0;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.book.tag,
    )) {
      Get.put(
        BookListController(
          type: 'book',
          isFavorite: false,
          alertWhenNoSourcePath: true,
        ),
        tag: _AppBookLibraryTab.book.tag,
      );
    }
    if (!Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.comic.tag,
    )) {
      Get.put(
        BookListController(
          type: 'comic',
          isFavorite: false,
          alertWhenNoSourcePath: true,
        ),
        tag: _AppBookLibraryTab.comic.tag,
      );
    }
    if (!Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.favorite.tag,
    )) {
      Get.put(
        BookListController(
          type: '',
          isFavorite: true,
          alertWhenNoSourcePath: true,
        ),
        tag: _AppBookLibraryTab.favorite.tag,
      );
    }
  }

  @override
  void dispose() {
    if (Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.book.tag,
    )) {
      Get.delete<BookListController>(
        tag: _AppBookLibraryTab.book.tag,
        force: true,
      );
    }
    if (Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.comic.tag,
    )) {
      Get.delete<BookListController>(
        tag: _AppBookLibraryTab.comic.tag,
        force: true,
      );
    }
    if (Get.isRegistered<BookListController>(
      tag: _AppBookLibraryTab.favorite.tag,
    )) {
      Get.delete<BookListController>(
        tag: _AppBookLibraryTab.favorite.tag,
        force: true,
      );
    }
    if (Get.isRegistered<BookHistoryController>()) {
      Get.delete<BookHistoryController>(force: true);
    }
    super.dispose();
  }

  void _openHome() {
    AppRoutes.toHome();
  }

  void _openSettings() {
    Get.to(
      () => Scaffold(
        appBar: AppBar(title: Text('setting'.tr)),
        body: const _AppBookSettingsTab(),
      ),
      preventDuplicates: false,
    );
  }

  BookListController? _currentLibraryController() {
    String? tag;
    if (_libraryIndex == 0) tag = _AppBookLibraryTab.book.tag;
    if (_libraryIndex == 1) tag = _AppBookLibraryTab.comic.tag;
    if (_libraryIndex == 2) tag = _AppBookLibraryTab.favorite.tag;
    if (tag == null) return null;
    if (!Get.isRegistered<BookListController>(tag: tag)) return null;
    return Get.find<BookListController>(tag: tag);
  }

  Future<void> _openSourceSheet(BookListController controller) async {
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
                            controller.selectedPaths.clear();
                            controller.refreshList(showLoading: false);
                          },
                          child: Text('reset'.tr),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (controller.availablePaths.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('no_path'.tr),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        itemCount: controller.availablePaths.length,
                        itemBuilder: (ctx, index) {
                          final item = controller.availablePaths[index];
                          final path = item.path;
                          final selected = controller.selectedPaths.contains(
                            path,
                          );
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: (val) {
                              if (val == true) {
                                controller.selectedPaths.add(path);
                              } else {
                                controller.selectedPaths.remove(path);
                              }
                              controller.refreshList(showLoading: false);
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

  List<_BookSortEntry> _bookSortEntries(BookListController controller) {
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
    if (controller.isFavoriteList) {
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

  String _currentSortLabel(BookListController controller) {
    for (final e in _bookSortEntries(controller)) {
      if (controller.sortBy.value == e.by &&
          controller.sortOrder.value == e.order) {
        return e.labelKey.tr;
      }
    }
    return 'sort'.tr;
  }

  Future<void> _openSortSheet(BookListController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final entries = _bookSortEntries(controller);
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
                        controller.sortBy.value == e.by &&
                            controller.sortOrder.value == e.order
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox(width: 24),
                    title: Text(e.labelKey.tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      controller.setSort(e.by, e.order);
                    },
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _modeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingLibraryTabs(bool isMultiSelect) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    if (_tabIndex != 0 || isMultiSelect) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      bottom: 5,
      child: Container(
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: (customColors?.oprationBarBgColor ?? theme.colorScheme.surface)
              .withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22.5),
        ),
        child: Row(
          children: [
            _modeChip(
              label: 'book_menu_library_book'.tr,
              selected: _libraryIndex == 0,
              onTap: () => setState(() => _libraryIndex = 0),
            ),
            _modeChip(
              label: 'book_menu_library_comic'.tr,
              selected: _libraryIndex == 1,
              onTap: () => setState(() => _libraryIndex = 1),
            ),
            _modeChip(
              label: 'favorites'.tr,
              selected: _libraryIndex == 2,
              onTap: () => setState(() => _libraryIndex = 2),
            ),
            _modeChip(
              label: 'book_menu_library_history'.tr,
              selected: _libraryIndex == 3,
              onTap: () {
                setState(() => _libraryIndex = 3);
                if (Get.isRegistered<BookHistoryController>()) {
                  Get.find<BookHistoryController>().refreshHistory(
                    showLoading: true,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTopBar({required bool isMultiSelect}) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    final ctrl = _currentLibraryController();
    final hasListCtrl = ctrl != null;
    final isHistory = _libraryIndex == 3;
    final activeSourceCount = ctrl?.selectedPaths.length ?? 0;
    final sourceActive = activeSourceCount > 0;

    final sortActive = hasListCtrl &&
        (ctrl.sortBy.value != BookListSortBy.createTime ||
            ctrl.sortOrder.value != BookListSortOrder.desc);

    if (isMultiSelect && ctrl != null) {
      return ColoredBox(
        color: barColor,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SizedBox(
              height: 50,
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
      );
    }

    return ColoredBox(
      color: barColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  CustomBorderedIconButton(
                    icon: Icons.home_outlined,
                    tooltip: 'app_files_back_home'.tr,
                    onTap: _openHome,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: hasListCtrl
                        ? _AppBookSearchBar(
                            key: ValueKey('app_book_search_$_libraryIndex'),
                            controller: ctrl,
                          )
                        : IgnorePointer(
                            child: Opacity(
                              opacity: 0.6,
                              child: CustomExpandableSearchBar(
                                hintText: 'book_list_search_hint'.tr,
                                defaultExpanded: true,
                              ),
                            ),
                          ),
                  ),
                  if (isHistory) ...[
                    const SizedBox(width: 8),
                    CustomBorderedIconButton(
                      icon: Icons.delete_sweep_outlined,
                      iconColor: theme.colorScheme.error,
                      onTap: () {
                        if (Get.isRegistered<BookHistoryController>()) {
                          Get.find<BookHistoryController>().clearHistory();
                        }
                      },
                    ),
                  ],
                  if (!isHistory) ...[
                    const SizedBox(width: 8),
                    CustomBorderedIconButton(
                      icon: Icons.sort_by_alpha,
                      tooltip: hasListCtrl
                          ? _currentSortLabel(ctrl)
                          : 'sort'.tr,
                      active: sortActive,
                      onTap: hasListCtrl && !isMultiSelect
                          ? () => _openSortSheet(ctrl)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    CustomBorderedIconButton(
                      icon:
                          sourceActive ? Icons.source : Icons.source_outlined,
                      tooltip: 'source'.tr,
                      active: sourceActive,
                      onTap: hasListCtrl && !isMultiSelect
                          ? () => _openSourceSheet(ctrl)
                          : null,
                    ),
                  ],
                  if (CurrentUserController.instance.isAdmin) ...[
                    const SizedBox(width: 8),
                    CustomBorderedIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'setting'.tr,
                      onTap: _openSettings,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody(bool isMultiSelect) {
    if (_tabIndex == 0) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _AppBookLibraryTabsBody(activeIndex: _libraryIndex),
          _buildFloatingLibraryTabs(isMultiSelect),
        ],
      );
    }
    if (_tabIndex == 1) {
      return const AppBookCustomListView();
    }
    if (_tabIndex == 2) {
      return const AppBookCollectionView();
    }
    if (_tabIndex == 3) {
      return const AppFolderViewPage(moduleType: FolderViewModuleType.book);
    }
    return Center(child: Text('not_implemented_yet'.tr));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;

    final ctrl = _currentLibraryController();

    Widget buildScaffold({required bool isMultiSelect}) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: barColor,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness,
            systemNavigationBarColor: barColor,
            systemNavigationBarIconBrightness:
                theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarDividerColor: barColor,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                if (_tabIndex == 0)
                  _buildHomeTopBar(isMultiSelect: isMultiSelect),
                Expanded(child: _buildTabBody(isMultiSelect)),
                if (isMultiSelect && ctrl != null)
                  AppBookMultiSelectBottomBar(controller: ctrl),
              ],
            ),
          ),
        ),
        bottomNavigationBar: isMultiSelect
            ? null
            : ColoredBox(
                color: barColor,
                child: SafeArea(
                  top: false,
                  child: BottomNavigationBar(
                    backgroundColor: barColor,
                    elevation: 0,
                    currentIndex: _tabIndex,
                    onTap: (i) {
                      if (i == _tabIndex) return;
                      setState(() => _tabIndex = i);
                    },
                    selectedItemColor: theme.colorScheme.primary,
                    unselectedItemColor: theme.colorScheme.onSurfaceVariant,
                    type: BottomNavigationBarType.fixed,
                    items: [
                      BottomNavigationBarItem(
                        icon: const Icon(Icons.home_outlined),
                        label: 'home'.tr,
                      ),
                      BottomNavigationBarItem(
                        icon: const Icon(Icons.bookmark_outline),
                        label: 'book_menu_book_list_custom'.tr,
                      ),
                      BottomNavigationBarItem(
                        icon: const Icon(Icons.collections_bookmark_outlined),
                        label: 'book_collection_title'.tr,
                      ),
                      BottomNavigationBarItem(
                        icon: const Icon(Icons.folder_outlined),
                        label: 'file'.tr,
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    if (ctrl == null) {
      return buildScaffold(isMultiSelect: false);
    }

    return Obx(() {
      return buildScaffold(isMultiSelect: ctrl.isMultiSelectMode.value);
    });
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

enum _AppBookLibraryTab { book, comic, favorite }

extension on _AppBookLibraryTab {
  String get tag {
    switch (this) {
      case _AppBookLibraryTab.book:
        return 'app_book_list_book';
      case _AppBookLibraryTab.comic:
        return 'app_book_list_comic';
      case _AppBookLibraryTab.favorite:
        return 'app_book_list_favorite';
    }
  }
}

/// 设置页：顶部 Tab 在「来源设置」与「缓存设置」之间切换，与音乐模块一致。
class _AppBookSettingsTab extends StatelessWidget {
  const _AppBookSettingsTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    final isAdmin = CurrentUserController.instance.isAdmin;
    if (!isAdmin) {
      return ColoredBox(
        color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
        child: SafeArea(bottom: false, child: const BookCacheDownloadView()),
      );
    }

    final tabs = <Widget>[Tab(text: 'settings_source'.tr)];
    final tabViews = <Widget>[
      MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: const KeyedSubtree(
          key: ValueKey('app_book_settings_source'),
          child: BookSourceSettingsView(),
        ),
      ),
    ];

    if (!DeviceUtils.isWeb) {
      tabs.add(Tab(text: 'book_menu_settings_cache_download'.tr));
      tabViews.add(
        const KeyedSubtree(
          key: ValueKey('app_book_settings_cache'),
          child: BookCacheDownloadView(),
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: ColoredBox(
        color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorColor: theme.colorScheme.primary,
                  tabs: tabs,
                ),
              ),
            ),
            Expanded(child: TabBarView(children: tabViews)),
          ],
        ),
      ),
    );
  }
}

class _AppBookLibraryTabsBody extends StatelessWidget {
  final int activeIndex;
  const _AppBookLibraryTabsBody({required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: activeIndex,
      children: const [
        _AppBookListSection(
          controllerTag: 'app_book_list_book',
          type: 'book',
          isFavorite: false,
        ),
        _AppBookListSection(
          controllerTag: 'app_book_list_comic',
          type: 'comic',
          isFavorite: false,
        ),
        _AppBookListSection(
          controllerTag: 'app_book_list_favorite',
          type: '',
          isFavorite: true,
        ),
        BookHistoryListView(),
      ],
    );
  }
}

class _AppBookListSection extends StatefulWidget {
  final String controllerTag;
  final String type;
  final bool isFavorite;
  const _AppBookListSection({
    required this.controllerTag,
    required this.type,
    required this.isFavorite,
  });

  @override
  State<_AppBookListSection> createState() => _AppBookListSectionState();
}

class _AppBookListSectionState extends State<_AppBookListSection> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ctrl = Get.isRegistered<BookListController>(tag: widget.controllerTag)
        ? Get.find<BookListController>(tag: widget.controllerTag)
        : null;
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.isRegistered<BookListController>(tag: widget.controllerTag)
        ? Get.find<BookListController>(tag: widget.controllerTag)
        : null;
    if (ctrl == null) return const SizedBox.shrink();

    return Obx(() {
      final showLoading = ctrl.loading.value && ctrl.items.isEmpty;
      final showEmpty =
          ctrl.firstLoaded.value && !ctrl.loading.value && ctrl.items.isEmpty;

      return CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (showLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (showEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: CustomNoData(text: 'no_data'.tr),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: BookListGrid(controller: ctrl, mobileLayout: true),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      );
    });
  }
}

class _AppBookSearchBar extends StatefulWidget {
  final BookListController controller;
  const _AppBookSearchBar({super.key, required this.controller});

  @override
  State<_AppBookSearchBar> createState() => _AppBookSearchBarState();
}

class _AppBookSearchBarState extends State<_AppBookSearchBar> {
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
      hintText: 'book_list_search_hint'.tr,
      onChanged: widget.controller.setSearchText,
      onClear: widget.controller.clearSearch,
      defaultExpanded: true,
    );
  }
}
