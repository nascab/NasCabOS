import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:NasCabOS/utils/popup_menu_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../controller/music_collection_controller.dart';
import 'music_collection_dialogs.dart';

class MusicCollectionTopBar extends StatelessWidget {
  final MusicCollectionController controller;
  final _sortButtonKey = GlobalKey();
  MusicCollectionTopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: customColors?.mainContentBgColor),
      child: Row(
        children: [
          CustomBorderedIconButton(
            icon: Icons.add,
            tooltip: 'create'.tr,
            onTap: () => MusicCollectionDialogs.showCreateDialog(
              context,
              controller: controller,
            ),
          ),
          const SizedBox(width: 4),
          _buildSortButton(context),
          const SizedBox(width: 4),
          const Expanded(child: SizedBox()),
          ConstrainedBox(
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
        ],
      ),
    );
  }

  Widget _buildSortButton(BuildContext context) {
    return Obx(() {
      final isActive =
          controller.searchController.text.isNotEmpty ||
          controller.sortField.value != 'create_time' ||
          controller.sortOrder.value != 'desc';

      return Container(
        key: _sortButtonKey,
        child: CustomBorderedIconButton(
          icon: Icons.sort_by_alpha,
          tooltip: 'sort'.tr,
          active: isActive,
          onTap: () => _openSortMenu(context),
        ),
      );
    });
  }

  Future<void> _openSortMenu(BuildContext context) async {
    final currentField = controller.sortField.value;
    final currentOrder = controller.sortOrder.value;

    bool isSelected(String field, String order) =>
        currentField == field && currentOrder == order;

    final selected = await PopupMenuUtil.showBelowButton<String>(
      context: context,
      buttonKey: _sortButtonKey,
      items: [
        PopupMenuItem(
          value: 'name_asc',
          child: _buildSortMenuItem(
            Icons.sort_by_alpha,
            'name_asc'.tr,
            isSelected('name', 'asc'),
          ),
        ),
        PopupMenuItem(
          value: 'name_desc',
          child: _buildSortMenuItem(
            Icons.sort_by_alpha,
            'name_desc'.tr,
            isSelected('name', 'desc'),
          ),
        ),
        PopupMenuItem(
          value: 'create_time_asc',
          child: _buildSortMenuItem(
            Icons.schedule,
            'create_time_asc'.tr,
            isSelected('create_time', 'asc'),
          ),
        ),
        PopupMenuItem(
          value: 'create_time_desc',
          child: _buildSortMenuItem(
            Icons.schedule,
            'create_time_desc'.tr,
            isSelected('create_time', 'desc'),
          ),
        ),
      ],
    );
    if (selected == null) return;
    final parts = selected.split('_');
    if (parts.isEmpty) return;
    final order = parts.last;
    final field = parts.sublist(0, parts.length - 1).join('_');
    controller.setSort(field: field, order: order);
  }

  Widget _buildSortMenuItem(IconData icon, String label, bool selected) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: selected ? const Icon(Icons.check, size: 18) : null,
        ),
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class AppMusicCollectionTopBar extends StatelessWidget {
  final MusicCollectionController controller;
  const AppMusicCollectionTopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Expanded(
              child: CustomExpandableSearchBar(
                hintText: 'search'.tr,
                controller: controller.searchController,
                onChanged: controller.onSearchChanged,
                onClear: controller.clearSearch,
                defaultExpanded: true,
              ),
            ),
            const SizedBox(width: 10),
            _buildSortButton(context),
            const SizedBox(width: 10),
            CustomBorderedIconButton(
              icon: Icons.add,
              tooltip: 'create'.tr,
              onTap: () => MusicCollectionDialogs.showCreateDialog(
                context,
                controller: controller,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortButton(BuildContext context) {
    return Obx(() {
      final isActive =
          controller.searchController.text.isNotEmpty ||
          controller.sortField.value != 'create_time' ||
          controller.sortOrder.value != 'desc';

      return CustomBorderedIconButton(
        icon: Icons.sort_by_alpha,
        tooltip: 'sort'.tr,
        active: isActive,
        onTap: () => _openSortSheet(context),
      );
    });
  }

  Future<void> _openSortSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            bool isSelected(String field, String order) =>
                controller.sortField.value == field &&
                controller.sortOrder.value == order;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                ListTile(
                  dense: true,
                  leading: isSelected('name', 'asc')
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('name_asc'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.setSort(field: 'name', order: 'asc');
                  },
                ),
                ListTile(
                  dense: true,
                  leading: isSelected('name', 'desc')
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('name_desc'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.setSort(field: 'name', order: 'desc');
                  },
                ),
                ListTile(
                  dense: true,
                  leading: isSelected('create_time', 'asc')
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('create_time_asc'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.setSort(field: 'create_time', order: 'asc');
                  },
                ),
                ListTile(
                  dense: true,
                  leading: isSelected('create_time', 'desc')
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : const SizedBox(width: 24),
                  title: Text('create_time_desc'.tr),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.setSort(field: 'create_time', order: 'desc');
                  },
                ),
              ],
            );
          }),
        );
      },
    );
  }
}
