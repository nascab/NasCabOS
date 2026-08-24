part of '../video_smart_album_list_view.dart';

class _TopBar extends StatelessWidget {
  final VideoSmartAlbumController controller;
  const _TopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: customColors?.mainContentBgColor),
      child: Row(
        children: [
          CustomBorderedIconButton(
            icon: Icons.add,
            tooltip: 'create'.tr,
            onTap: () => _showCreateDialog(context, controller),
          ),
          const SizedBox(width: 4),
          Obx(() {
            final cur =
                '${controller.sortField.value}_${controller.sortOrder.value}';
            return CustomPopupSelectButton<String>(
              icon: Icons.sort_by_alpha,
              tooltip: 'sort'.tr,
              value: cur,
              defaultValue: 'create_time_desc',
              items: [
                CustomPopupSelectItem(
                  value: 'name_asc',
                  label: 'photo_album_sort_name_asc'.tr,
                  icon: Icons.sort_by_alpha,
                ),
                CustomPopupSelectItem(
                  value: 'name_desc',
                  label: 'photo_album_sort_name_desc'.tr,
                  icon: Icons.sort_by_alpha,
                ),
                CustomPopupSelectItem(
                  value: 'create_time_asc',
                  label: 'photo_album_sort_create_time_asc'.tr,
                  icon: Icons.schedule,
                ),
                CustomPopupSelectItem(
                  value: 'create_time_desc',
                  label: 'photo_album_sort_create_time_desc'.tr,
                  icon: Icons.schedule,
                ),
              ],
              onSelected: (next) {
                final parts = next.split('_');
                if (parts.isEmpty) return;
                final order = parts.last;
                final field = parts.sublist(0, parts.length - 1).join('_');
                controller.setSort(field: field, order: order);
              },
            );
          }),
          const SizedBox(width: 10),
          const Spacer(),
          CustomExpandableSearchBar(
            hintText: 'search'.tr,
            onChanged: controller.onSearchChanged,
            onClear: controller.clearSearch,
            expandedWidth: 120,
          ),
        ],
      ),
    );
  }
}
