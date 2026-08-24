import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../../../utils/popup_menu_util.dart';
import '../../controller/book_custom_list_controller.dart';
import 'book_custom_list_dialogs.dart';

class BookCustomListTopBar extends StatefulWidget {
  final BookCustomListController controller;
  final bool selectionMode;
  const BookCustomListTopBar({
    super.key,
    required this.controller,
    required this.selectionMode,
  });

  @override
  State<BookCustomListTopBar> createState() => _BookCustomListTopBarState();
}

class _BookCustomListTopBarState extends State<BookCustomListTopBar> {
  final _sortKey = GlobalKey();

  BookCustomListController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: customColors!.mainContentBgColor,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(widget.selectionMode ? 30 : 0),
        ),
      ),
      child: Row(
        children: [
          if (widget.selectionMode) ...[
            IconButton(
              tooltip: 'back'.tr,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text(
                'book_list_select'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Get.textTheme.titleMedium,
              ),
            ),
          ] else ...[
            CustomBorderedIconButton(
              icon: Icons.add,
              tooltip: 'create'.tr,
              onTap: () => BookCustomListDialogs.showCreateDialog(
                context,
                controller: controller,
              ),
            ),
            const SizedBox(width: 4),
            Obx(() {
              final field = controller.sortBy.value;
              final order = controller.sortOrder.value;
              final isActive =
                  field != 'create_time' || order != 'desc';
              return CustomBorderedIconButton(
                key: _sortKey,
                icon: Icons.sort_by_alpha,
                tooltip: 'sort'.tr,
                active: isActive,
                onTap: () async {
                  final result =
                      await PopupMenuUtil.showBelowButton<String>(
                        context: context,
                        buttonKey: _sortKey,
                        items: _buildSortItems(field, order),
                      );
                  if (result != null) {
                    final parts = result.split(':');
                    if (parts.length == 2) {
                      controller.setSort(
                        field: parts[0],
                        order: parts[1],
                      );
                    }
                  }
                },
              );
            }),
            const Spacer(),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: SizedBox(
                    width: double.infinity,
                    child: CustomExpandableSearchBar(
                      controller: controller.searchController,
                      hintText: 'book_list_search_hint'.tr,
                      onChanged: controller.onSearchChanged,
                      onClear: controller.clearSearch,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildSortItems(
    String currentField,
    String currentOrder,
  ) {
    final items = <PopupMenuEntry<String>>[];

    void addItem(
      String field,
      String order,
      IconData icon,
      String label,
    ) {
      final selected = field == currentField && order == currentOrder;
      items.add(
        PopupMenuItem<String>(
          value: '$field:$order',
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

    addItem('name', 'asc', Icons.sort_by_alpha, 'name_asc'.tr);
    addItem('name', 'desc', Icons.sort_by_alpha, 'name_desc'.tr);

    items.add(const PopupMenuDivider());

    addItem('create_time', 'asc', Icons.access_time, 'create_time_asc'.tr);
    addItem(
      'create_time',
      'desc',
      Icons.access_time,
      'create_time_desc'.tr,
    );

    return items;
  }
}
