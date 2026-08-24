import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_hover_menu_anchor.dart';
import '../../controller/music_list_controller.dart';

class MusicListSortMenu extends StatelessWidget {
  final MusicListController controller;
  const MusicListSortMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      bool isSelected(MusicListSortBy by, MusicListSortOrder order) =>
          controller.sortBy.value == by && controller.sortOrder.value == order;

      Widget leading(bool selected) => selected
          ? const Icon(Icons.check, size: 18)
          : const SizedBox(width: 18);

      return CustomHoverMenuAnchor(
        menuChildren: [
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.title,
              MusicListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.title, MusicListSortOrder.asc),
            ),
            child: Text('music_list_sort_title_asc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.title,
              MusicListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.title, MusicListSortOrder.desc),
            ),
            child: Text('music_list_sort_title_desc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.year,
              MusicListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.year, MusicListSortOrder.desc),
            ),
            child: Text('music_list_sort_year_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.year,
              MusicListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.year, MusicListSortOrder.asc),
            ),
            child: Text('music_list_sort_year_asc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.duration,
              MusicListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.duration, MusicListSortOrder.desc),
            ),
            child: Text('music_list_sort_duration_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.duration,
              MusicListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.duration, MusicListSortOrder.asc),
            ),
            child: Text('music_list_sort_duration_asc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.ctime,
              MusicListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.ctime, MusicListSortOrder.desc),
            ),
            child: Text('create_time_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicListSortBy.ctime,
              MusicListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicListSortBy.ctime, MusicListSortOrder.asc),
            ),
            child: Text('create_time_asc'.tr),
          ),
          if (controller.isFavoriteList) ...[
            const Divider(height: 1),
            MenuItemButton(
              onPressed: () => controller.setSort(
                MusicListSortBy.favoriteTime,
                MusicListSortOrder.desc,
              ),
              leadingIcon: leading(
                isSelected(
                  MusicListSortBy.favoriteTime,
                  MusicListSortOrder.desc,
                ),
              ),
              child: Text('music_list_sort_favorite_time_desc'.tr),
            ),
            MenuItemButton(
              onPressed: () => controller.setSort(
                MusicListSortBy.favoriteTime,
                MusicListSortOrder.asc,
              ),
              leadingIcon: leading(
                isSelected(
                  MusicListSortBy.favoriteTime,
                  MusicListSortOrder.asc,
                ),
              ),
              child: Text('music_list_sort_favorite_time_asc'.tr),
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
