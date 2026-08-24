import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/book/book_list/controller/book_custom_list_controller.dart';
import 'package:NasCabOS/modules/book/book_list/service/book_custom_list_api_service.dart';
import 'package:NasCabOS/modules/book/book_list/view/parts/book_custom_list_card.dart';
import 'package:NasCabOS/modules/book/book_list/view/parts/book_custom_list_dialogs.dart';
import 'package:NasCabOS/modules/book/list/view/app_book_sub_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class AppBookCustomListView extends StatefulWidget {
  const AppBookCustomListView({super.key});

  @override
  State<AppBookCustomListView> createState() => _AppBookCustomListViewState();
}

class _AppBookCustomListViewState extends State<AppBookCustomListView> {
  final String _tag = 'app_book_custom_list_view';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<BookCustomListController>(tag: _tag)) {
      Get.put(BookCustomListController(), tag: _tag);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (Get.isRegistered<BookCustomListController>(tag: _tag)) {
      Get.delete<BookCustomListController>(tag: _tag);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final ctrl = Get.find<BookCustomListController>(tag: _tag);
      ctrl.loadMore();
    }
  }

  void _openHome() {
    Get.offAllNamed(AppRoutes.home);
  }

  void _openDetail(BookCustomListItem item) {
    Get.to(
      () => AppBookSubListPage(listId: item.id, title: item.name),
      preventDuplicates: false,
    );
  }

  void _showSortSheet(BookCustomListController controller) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Material(
          color: theme.colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SortItem(
                label: 'create_time_desc'.tr,
                selected:
                    controller.sortBy.value == 'create_time' &&
                    controller.sortOrder.value == 'desc',
                onTap: () {
                  controller.setSort(field: 'create_time', order: 'desc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'create_time_asc'.tr,
                selected:
                    controller.sortBy.value == 'create_time' &&
                    controller.sortOrder.value == 'asc',
                onTap: () {
                  controller.setSort(field: 'create_time', order: 'asc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'name_asc'.tr,
                selected:
                    controller.sortBy.value == 'name' &&
                    controller.sortOrder.value == 'asc',
                onTap: () {
                  controller.setSort(field: 'name', order: 'asc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'name_desc'.tr,
                selected:
                    controller.sortBy.value == 'name' &&
                    controller.sortOrder.value == 'desc',
                onTap: () {
                  controller.setSort(field: 'name', order: 'desc');
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _currentSortLabel(BookCustomListController controller) {
    final field = controller.sortBy.value;
    final order = controller.sortOrder.value;
    if (field == 'create_time' && order == 'desc') return 'create_time_desc'.tr;
    if (field == 'create_time' && order == 'asc') return 'create_time_asc'.tr;
    if (field == 'name' && order == 'asc') return 'name_asc'.tr;
    if (field == 'name' && order == 'desc') return 'name_desc'.tr;
    return 'sort'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    final ctrl = Get.find<BookCustomListController>(tag: _tag);

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: barColor,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: theme.brightness,
          systemNavigationBarColor: barColor,
          systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarDividerColor: barColor,
        ),
        child: Column(
          children: [
            ColoredBox(
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
                            child: CustomExpandableSearchBar(
                              controller: ctrl.searchController,
                              hintText: 'book_list_search_hint'.tr,
                              onChanged: ctrl.onSearchChanged,
                              onClear: ctrl.clearSearch,
                              defaultExpanded: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Obx(() {
                            final isDefaultSort =
                                ctrl.sortBy.value == 'create_time' &&
                                ctrl.sortOrder.value == 'desc';
                            return CustomBorderedIconButton(
                              icon: Icons.sort_by_alpha,
                              tooltip: _currentSortLabel(ctrl),
                              active: !isDefaultSort,
                              onTap: () => _showSortSheet(ctrl),
                            );
                          }),
                          const SizedBox(width: 10),
                          CustomBorderedIconButton(
                            icon: Icons.add,
                            tooltip: 'create'.tr,
                            onTap: () {
                              BookCustomListDialogs.showCreateDialog(
                                context,
                                controller: ctrl,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Obx(() {
                  if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ctrl.items.isEmpty) {
                    return CustomNoData(text: 'no_data'.tr);
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.crossAxisExtent;
                            final isMobile = width < 750;
                            return SliverGrid(
                              gridDelegate: isMobile
                                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 1,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1.55,
                                    )
                                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 250,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.65,
                                    ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = ctrl.items[index];
                                return BookCustomListCard(
                                  item: item,
                                  selectionMode: false,
                                  onOpen: () => _openDetail(item),
                                  onRename: () =>
                                      BookCustomListDialogs.showRenameDialog(
                                        context,
                                        controller: ctrl,
                                        item: item,
                                      ),
                                  onDelete: () =>
                                      BookCustomListDialogs.confirmDelete(
                                        context,
                                        controller: ctrl,
                                        item: item,
                                      ),
                                );
                              }, childCount: ctrl.items.length),
                            );
                          },
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 92)),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : const SizedBox(width: 24),
      title: Text(label),
      onTap: onTap,
    );
  }
}
