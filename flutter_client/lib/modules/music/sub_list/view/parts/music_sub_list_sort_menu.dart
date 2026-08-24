import 'package:NasCabOS/modules/base/components/custom_icon_button.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get/get.dart';
import '../../controller/music_sub_list_controller.dart';

class MusicSubListSortMenu extends StatelessWidget {
  final MusicSubListController controller;
  const MusicSubListSortMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      bool isSelected(MusicSubListSortBy by, MusicSubListSortOrder order) =>
          controller.sortBy.value == by && controller.sortOrder.value == order;

      Widget leading(bool selected) => selected
          ? const Icon(Icons.check, size: 18)
          : const SizedBox(width: 18);

      return _HoverCircleMenuAnchor(
        menuChildren: [
          if (controller.isFavorite)
            MenuItemButton(
              onPressed: () => controller.setSort(
                MusicSubListSortBy.favoriteTime,
                MusicSubListSortOrder.desc,
              ),
              leadingIcon: leading(
                isSelected(
                  MusicSubListSortBy.favoriteTime,
                  MusicSubListSortOrder.desc,
                ),
              ),
              child: Text('music_list_sort_favorite_time_desc'.tr),
            ),
          if (controller.isFavorite)
            MenuItemButton(
              onPressed: () => controller.setSort(
                MusicSubListSortBy.favoriteTime,
                MusicSubListSortOrder.asc,
              ),
              leadingIcon: leading(
                isSelected(
                  MusicSubListSortBy.favoriteTime,
                  MusicSubListSortOrder.asc,
                ),
              ),
              child: Text('music_list_sort_favorite_time_asc'.tr),
            ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.filename,
              MusicSubListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(
                MusicSubListSortBy.filename,
                MusicSubListSortOrder.asc,
              ),
            ),
            child: Text('music_list_sort_filename_asc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.filename,
              MusicSubListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(
                MusicSubListSortBy.filename,
                MusicSubListSortOrder.desc,
              ),
            ),
            child: Text('music_list_sort_filename_desc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.title,
              MusicSubListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicSubListSortBy.title, MusicSubListSortOrder.asc),
            ),
            child: Text('music_list_sort_title_asc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.title,
              MusicSubListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicSubListSortBy.title, MusicSubListSortOrder.desc),
            ),
            child: Text('music_list_sort_title_desc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.duration,
              MusicSubListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(
                MusicSubListSortBy.duration,
                MusicSubListSortOrder.desc,
              ),
            ),
            child: Text('music_list_sort_duration_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.duration,
              MusicSubListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(
                MusicSubListSortBy.duration,
                MusicSubListSortOrder.asc,
              ),
            ),
            child: Text('music_list_sort_duration_asc'.tr),
          ),
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.ctime,
              MusicSubListSortOrder.desc,
            ),
            leadingIcon: leading(
              isSelected(MusicSubListSortBy.ctime, MusicSubListSortOrder.desc),
            ),
            child: Text('create_time_desc'.tr),
          ),
          MenuItemButton(
            onPressed: () => controller.setSort(
              MusicSubListSortBy.ctime,
              MusicSubListSortOrder.asc,
            ),
            leadingIcon: leading(
              isSelected(MusicSubListSortBy.ctime, MusicSubListSortOrder.asc),
            ),
            child: Text('create_time_asc'.tr),
          ),
        ],
        icon: Icons.sort_by_alpha,
        tooltip: '',
      );
    });
  }
}

class _HoverCircleMenuAnchor extends StatefulWidget {
  final List<Widget> menuChildren;
  final IconData icon;
  final String tooltip;

  const _HoverCircleMenuAnchor({
    required this.menuChildren,
    required this.icon,
    required this.tooltip,
  });

  @override
  State<_HoverCircleMenuAnchor> createState() => _HoverCircleMenuAnchorState();
}

class _HoverCircleMenuAnchorState extends State<_HoverCircleMenuAnchor> {
  MenuController? _menuController;
  Timer? _closeTimer;
  bool _overButton = false;
  bool _overMenu = false;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 160), () {
      final ctrl = _menuController;
      if (ctrl == null) return;
      if (_overButton || _overMenu) return;
      ctrl.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wrappedChildren = widget.menuChildren
        .map(
          (menuChild) => MouseRegion(
            onEnter: (_) {
              _overMenu = true;
              _closeTimer?.cancel();
            },
            onExit: (_) {
              _overMenu = false;
              _scheduleClose();
            },
            child: menuChild,
          ),
        )
        .toList(growable: false);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
      ),
      menuChildren: wrappedChildren,
      builder: (context, menuController, child) {
        _menuController = menuController;
        return MouseRegion(
          onEnter: (_) {
            _overButton = true;
            _closeTimer?.cancel();
            menuController.open();
          },
          onExit: (_) {
            _overButton = false;
            _scheduleClose();
          },

          child: CustomIconButton(
            borderRadius: 999,
            borderSide: BorderSide(color: theme.dividerColor),
            icon: widget.icon,
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
          ),
        );
      },
    );
  }
}
