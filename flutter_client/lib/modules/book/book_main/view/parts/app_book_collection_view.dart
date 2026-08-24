import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/book/collection/controller/book_collection_controller.dart';
import 'package:NasCabOS/modules/book/collection/models/book_collection_model.dart';
import 'package:NasCabOS/modules/book/collection/view/parts/book_collection_card.dart';
import 'package:NasCabOS/modules/book/collection/view/parts/book_collection_dialogs.dart';
import 'package:NasCabOS/modules/book/list/view/app_book_sub_list_page.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class AppBookCollectionView extends StatefulWidget {
  const AppBookCollectionView({super.key});

  @override
  State<AppBookCollectionView> createState() => _AppBookCollectionViewState();
}

class _AppBookCollectionViewState extends State<AppBookCollectionView> {
  final String _tag = 'app_book_collection_view';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<BookCollectionController>(tag: _tag)) {
      Get.put(BookCollectionController(), tag: _tag);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (Get.isRegistered<BookCollectionController>(tag: _tag)) {
      Get.delete<BookCollectionController>(tag: _tag);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final ctrl = Get.find<BookCollectionController>(tag: _tag);
      ctrl.loadMore();
    }
  }

  void _openHome() {
    Get.offAllNamed(AppRoutes.home);
  }

  void _openDetail(BookCollectionItem item) {
    Get.to(
      () => AppBookSubListPage(collectionId: item.id, title: item.name),
      preventDuplicates: false,
    );
  }

  void _showSortSheet(BookCollectionController controller) {
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
                    controller.sortField.value == 'create_time' &&
                    controller.sortOrder.value == 'desc',
                onTap: () {
                  controller.setSort(field: 'create_time', order: 'desc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'create_time_asc'.tr,
                selected:
                    controller.sortField.value == 'create_time' &&
                    controller.sortOrder.value == 'asc',
                onTap: () {
                  controller.setSort(field: 'create_time', order: 'asc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'name_asc'.tr,
                selected:
                    controller.sortField.value == 'name' &&
                    controller.sortOrder.value == 'asc',
                onTap: () {
                  controller.setSort(field: 'name', order: 'asc');
                  Navigator.pop(ctx);
                },
              ),
              _SortItem(
                label: 'name_desc'.tr,
                selected:
                    controller.sortField.value == 'name' &&
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

  String _currentSortLabel(BookCollectionController controller) {
    final field = controller.sortField.value;
    final order = controller.sortOrder.value;
    if (field == 'create_time' && order == 'desc') return 'create_time_desc'.tr;
    if (field == 'create_time' && order == 'asc') return 'create_time_asc'.tr;
    if (field == 'name' && order == 'asc') return 'name_asc'.tr;
    if (field == 'name' && order == 'desc') return 'name_desc'.tr;
    return 'sort'.tr;
  }

  void _showHelp(BookCollectionItem item) {
    final content = item.pathList.join('\n');
    DialogUtil.showInfoDialog(
      title: 'path'.tr,
      content: content.isEmpty ? 'no_path'.tr : content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    final ctrl = Get.find<BookCollectionController>(tag: _tag);

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
                                ctrl.sortField.value == 'create_time' &&
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
                              BookCollectionDialogs.showCreateDialog(
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
                                      childAspectRatio: 1.45,
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
                                return Stack(
                                  children: [
                                    BookCollectionCard(
                                      collection: item,
                                      onOpen: () => _openDetail(item),
                                      onEdit: () =>
                                          BookCollectionDialogs.showEditDialog(
                                            context,
                                            controller: ctrl,
                                            collection: item,
                                          ),
                                      onDelete: () =>
                                          BookCollectionDialogs.confirmDelete(
                                            context,
                                            controller: ctrl,
                                            collection: item,
                                          ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.help_outline,
                                          color: Colors.white,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        onPressed: () => _showHelp(item),
                                        tooltip: 'path'.tr,
                                      ),
                                    ),
                                  ],
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
