import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../../../utils/popup_menu_util.dart';
import '../../controller/book_list_controller.dart';

class BookListTopBar extends StatefulWidget {
  final BookListController controller;
  const BookListTopBar({super.key, required this.controller});

  @override
  State<BookListTopBar> createState() => _BookListTopBarState();
}

class _BookListTopBarState extends State<BookListTopBar> {
  final _sourceKey = GlobalKey();

  BookListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
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
                          child: BookListSourcePanel(controller: controller),
                        ),
                      ),
                    ],
                  );
                },
              );
            }),
            const SizedBox(width: 4),
            _SortButton(controller: controller),
            const SizedBox(width: 4),
            Obx(() {
              final scale = controller.coverScale.value;
              final canDecrease =
                  scale > BookListController.coverScaleMin + 0.001;
              final canIncrease =
                  scale < BookListController.coverScaleMax - 0.001;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomBorderedIconButton(
                    icon: Icons.zoom_out,
                    tooltip: 'zoom_out'.tr,
                    enabled: canDecrease,
                    onTap: controller.decreaseCoverScale,
                  ),
                  const SizedBox(width: 4),
                  CustomBorderedIconButton(
                    icon: Icons.zoom_in,
                    tooltip: 'zoom_in'.tr,
                    enabled: canIncrease,
                    onTap: controller.increaseCoverScale,
                  ),
                ],
              );
            }),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: SizedBox(
                width: double.infinity,
                child: BookListSearchBar(controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookListSourcePanel extends StatelessWidget {
  final BookListController controller;
  const BookListSourcePanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('source'.tr, style: Get.textTheme.titleSmall),
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
          SizedBox(
            height: 150,
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
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
                            const Icon(
                              Icons.cancel,
                              color: Colors.red,
                              size: 16,
                            ),
                        ],
                      ),
                      value: isSelected,
                      onChanged: (val) {
                        if (val == true) {
                          controller.selectedPaths.add(path);
                        } else {
                          controller.selectedPaths.remove(path);
                        }
                        controller.refreshList(showLoading: false);
                      },
                    );
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class BookListSearchBar extends StatefulWidget {
  final BookListController controller;
  const BookListSearchBar({super.key, required this.controller});

  @override
  State<BookListSearchBar> createState() => _BookListSearchBarState();
}

class _BookListSearchBarState extends State<BookListSearchBar> {
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
    );
  }
}

class _SortButton extends StatefulWidget {
  final BookListController controller;
  const _SortButton({required this.controller});

  @override
  State<_SortButton> createState() => _SortButtonState();
}

class _SortButtonState extends State<_SortButton> {
  final GlobalKey _buttonKey = GlobalKey();

  void _handleSortResult(String? value) {
    if (value == null) return;
    final parts = value.split(':');
    if (parts.length != 2) return;

    final by = switch (parts[0]) {
      'create_time' => BookListSortBy.createTime,
      'name' => BookListSortBy.name,
      'favorite_time' => BookListSortBy.favoriteTime,
      _ => null,
    };
    if (by == null) return;

    final order = switch (parts[1]) {
      'asc' => BookListSortOrder.asc,
      'desc' => BookListSortOrder.desc,
      _ => null,
    };
    if (order == null) return;

    widget.controller.setSort(by, order);
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    bool Function(BookListSortBy, BookListSortOrder) isSelected,
  ) {
    final items = <PopupMenuEntry<String>>[];

    void addItem(String value, IconData icon, String label, bool selected) {
      items.add(
        PopupMenuItem<String>(
          value: value,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: selected ? const Icon(Icons.check, size: 18) : null,
              ),
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      );
    }

    addItem(
      'create_time:desc',
      Icons.access_time,
      'create_time_desc'.tr,
      isSelected(BookListSortBy.createTime, BookListSortOrder.desc),
    );
    addItem(
      'create_time:asc',
      Icons.access_time,
      'create_time_asc'.tr,
      isSelected(BookListSortBy.createTime, BookListSortOrder.asc),
    );

    items.add(const PopupMenuDivider());

    addItem(
      'name:asc',
      Icons.sort_by_alpha,
      'name_asc'.tr,
      isSelected(BookListSortBy.name, BookListSortOrder.asc),
    );
    addItem(
      'name:desc',
      Icons.sort_by_alpha,
      'name_desc'.tr,
      isSelected(BookListSortBy.name, BookListSortOrder.desc),
    );

    if (widget.controller.isFavoriteList) {
      items.add(const PopupMenuDivider());
      addItem(
        'favorite_time:desc',
        Icons.favorite,
        'book_list_sort_favorite_time_desc'.tr,
        isSelected(BookListSortBy.favoriteTime, BookListSortOrder.desc),
      );
      addItem(
        'favorite_time:asc',
        Icons.favorite,
        'book_list_sort_favorite_time_asc'.tr,
        isSelected(BookListSortBy.favoriteTime, BookListSortOrder.asc),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sortBy = widget.controller.sortBy.value;
      final sortOrder = widget.controller.sortOrder.value;
      final c = widget.controller;

      final defaultBy = (c.seriesIndexId != null && c.seriesIndexId! > 0)
          ? BookListSortBy.name
          : c.isFavoriteList
          ? BookListSortBy.favoriteTime
          : BookListSortBy.createTime;
      final defaultOrder = (c.seriesIndexId != null && c.seriesIndexId! > 0)
          ? BookListSortOrder.asc
          : BookListSortOrder.desc;
      final isActive = sortBy != defaultBy || sortOrder != defaultOrder;

      bool isSelected(BookListSortBy by, BookListSortOrder order) =>
          sortBy == by && sortOrder == order;

      return CustomBorderedIconButton(
        key: _buttonKey,
        icon: Icons.sort_by_alpha,
        tooltip: 'sort'.tr,
        active: isActive,
        onTap: () async {
          final result = await PopupMenuUtil.showBelowButton<String>(
            context: context,
            buttonKey: _buttonKey,
            items: _buildMenuItems(isSelected),
          );
          _handleSortResult(result);
        },
      );
    });
  }
}
