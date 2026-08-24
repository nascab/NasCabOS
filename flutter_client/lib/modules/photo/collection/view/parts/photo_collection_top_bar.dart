part of '../photo_collection_list_view.dart';

class _TopBar extends StatefulWidget {
  final PhotoCollectionController controller;
  const _TopBar({required this.controller});

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  PhotoCollectionController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: customColors?.mainContentBgColor),
      child: Row(
        children: [
          // 创建按钮
          CustomBorderedIconButton(
            icon: Icons.add,
            onTap: () => _showCreateDialog(context, controller),
            tooltip: 'create'.tr,
          ),
          const SizedBox(width: 4),
          // 排序筛选
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Obx(
              () => CustomPopupSelectButton<String>(
                tooltip: 'sort'.tr,
                icon: Icons.sort_by_alpha,
                value: '${controller.sortField.value}_${controller.sortOrder.value}',
                defaultValue: 'create_time_desc',
                items: [
                  CustomPopupSelectItem(value: 'name_asc', label: 'photo_album_sort_name_asc'.tr, icon: Icons.sort_by_alpha),
                  CustomPopupSelectItem(value: 'name_desc', label: 'photo_album_sort_name_desc'.tr, icon: Icons.sort_by_alpha),
                  CustomPopupSelectItem(value: 'create_time_asc', label: 'photo_album_sort_create_time_asc'.tr, icon: Icons.schedule),
                  CustomPopupSelectItem(value: 'create_time_desc', label: 'photo_album_sort_create_time_desc'.tr, icon: Icons.schedule),
                ],
                onSelected: (value) {
                  final parts = value.split('_');
                  final order = parts.last;
                  final field = parts.sublist(0, parts.length - 1).join('_');
                  controller.setSort(field: field, order: order);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: CustomExpandableSearchBar(
                    hintText: 'search'.tr,
                    onChanged: controller.onSearchChanged,
                    onClear: controller.clearSearch,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
