import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/modules/book/list/controller/book_list_controller.dart';

class AppBookMultiSelectBottomBar extends StatelessWidget {
  final BookListController controller;
  const AppBookMultiSelectBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surface;
    return Obx(() {
      if (!controller.isMultiSelectMode.value) return const SizedBox.shrink();
      final disabled = controller.selectedItems.isEmpty;
      return Container(
        color: bgColor,
        child: SafeArea(
          top: false,
          child: Container(
            height: 65,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _barAction(
                  context,
                  icon: Icons.delete_outline,
                  label: 'delete'.tr,
                  enabled: !disabled,
                  danger: true,
                  onTap: controller.deleteSelected,
                ),
                _barAction(
                  context,
                  icon: Icons.favorite_border,
                  label: 'favorites'.tr,
                  enabled: !disabled,
                  onTap: controller.toggleFavoriteSelected,
                ),
                _barAction(
                  context,
                  icon: Icons.playlist_add,
                  label: 'add_to_book_list'.tr,
                  enabled: !disabled,
                  onTap: controller.addToBookListSelected,
                ),
                if (controller.isInCustomList)
                  _barAction(
                    context,
                    icon: Icons.playlist_remove,
                    label: 'remove_from_book_list'.tr,
                    enabled: !disabled,
                    onTap: controller.removeFromBookListSelected,
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  static Widget _barAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: enabled ? color : theme.disabledColor),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: enabled ? color : theme.disabledColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
