import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_hover_menu_anchor.dart';
import '../../controller/book_list_controller.dart';

class BookListSortMenu extends StatelessWidget {
  final BookListController controller;
  const BookListSortMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      bool isSelected(BookListSortBy by, BookListSortOrder order) =>
          controller.sortBy.value == by && controller.sortOrder.value == order;

      Widget leading(bool selected) => selected
          ? const Icon(Icons.check, size: 18)
          : const SizedBox(width: 18);

      return CustomHoverMenuAnchor(
        menuChildren: [
          // MenuItemButton(
          //   onPressed: () => controller.setSort(
          //     BookListSortBy.viewTime,
          //     BookListSortOrder.desc,
          //   ),
          //   leadingIcon: leading(
          //     isSelected(BookListSortBy.viewTime, BookListSortOrder.desc),
          //   ),
          //   child: Text('book_list_sort_view_time_desc'.tr),
          // ),
          // MenuItemButton(
          //   onPressed: () => controller.setSort(
          //     BookListSortBy.viewTime,
          //     BookListSortOrder.asc,
          //   ),
          //   leadingIcon: leading(
          //     isSelected(BookListSortBy.viewTime, BookListSortOrder.asc),
          //   ),
          //   child: Text('book_list_sort_view_time_asc'.tr),
          // ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              BookListSortBy.createTime,
              BookListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(BookListSortBy.createTime, BookListSortOrder.desc),
            ),
            child: Text('create_time_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              BookListSortBy.createTime,
              BookListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(BookListSortBy.createTime, BookListSortOrder.asc),
            ),
            child: Text('create_time_asc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () =>
                controller.setSort(BookListSortBy.name, BookListSortOrder.asc),
            leadingIcon: leading(
              isSelected(BookListSortBy.name, BookListSortOrder.asc),
            ),
            child: Text('name_asc'.tr),
          ),
          MenuItemButton(
            onPressed: () =>
                controller.setSort(BookListSortBy.name, BookListSortOrder.desc),
            leadingIcon: leading(
              isSelected(BookListSortBy.name, BookListSortOrder.desc),
            ),
            child: Text('name_desc'.tr),
          ),
          if (controller.isFavoriteList) ...[
            const Divider(height: 1),
            MenuItemButton(
              onPressed: () => controller.setSort(
                BookListSortBy.favoriteTime,
                BookListSortOrder.desc,
              ),
              leadingIcon: leading(
                isSelected(BookListSortBy.favoriteTime, BookListSortOrder.desc),
              ),
              child: Text('book_list_sort_favorite_time_desc'.tr),
            ),
            MenuItemButton(
              onPressed: () => controller.setSort(
                BookListSortBy.favoriteTime,
                BookListSortOrder.asc,
              ),
              leadingIcon: leading(
                isSelected(BookListSortBy.favoriteTime, BookListSortOrder.asc),
              ),
              child: Text('book_list_sort_favorite_time_asc'.tr),
            ),
          ],
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_by_alpha, size: 18),
            const SizedBox(width: 6),
            Text('sort'.tr),
          ],
        ),
      );
    });
  }
}
