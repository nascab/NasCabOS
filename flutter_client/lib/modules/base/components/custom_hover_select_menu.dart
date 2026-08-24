import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/custom_colors.dart';
import 'custom_hover_menu_anchor.dart';
import 'custom_inset_border_shell.dart';

class CustomHoverSelectMenuItem<T> {
  final T value;
  final String label;
  final IconData icon;
  final bool enabled;

  const CustomHoverSelectMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
  });
}

class CustomHoverSelectMenu<T> extends StatefulWidget {
  final T value;
  final List<CustomHoverSelectMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData buttonIcon;
  final double buttonIconSize;
  final double itemIconSize;
  final double height;
  final double radius;
  final EdgeInsetsGeometry buttonPadding;
  final Offset menuOffset;
  final bool showSelectedCheck;
  final CustomHoverMenuTriggerMode triggerMode;

  const CustomHoverSelectMenu({
    super.key,
    required this.value,
    required this.items,
    required this.onSelected,
    required this.buttonIcon,
    this.buttonIconSize = 18,
    this.itemIconSize = 18,
    this.height = 38,
    this.radius = 10,
    this.buttonPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
    this.menuOffset = const Offset(0, 6),
    this.showSelectedCheck = true,
    this.triggerMode = CustomHoverMenuTriggerMode.click,
  });

  @override
  State<CustomHoverSelectMenu<T>> createState() =>
      _CustomHoverSelectMenuState<T>();
}

class _CustomHoverSelectMenuState<T> extends State<CustomHoverSelectMenu<T>> {
  static MenuController? _activeMenuController;

  MenuController? _menuController;
  Timer? _closeTimer;
  bool _overButton = false;
  bool _overMenu = false;
  bool _isOpen = false;

  @override
  void dispose() {
    _closeTimer?.cancel();
    final ctrl = _menuController;
    if (ctrl != null && identical(_activeMenuController, ctrl)) {
      _activeMenuController = null;
    }
    super.dispose();
  }

  void _openMenu(MenuController ctrl) {
    final active = _activeMenuController;
    if (active != null && !identical(active, ctrl)) {
      active.close();
    }
    _activeMenuController = ctrl;
    _isOpen = true;
    ctrl.open();
  }

  void _closeMenu() {
    final ctrl = _menuController;
    if (ctrl == null) return;
    _isOpen = false;
    ctrl.close();
    if (identical(_activeMenuController, ctrl)) {
      _activeMenuController = null;
    }
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 160), () {
      final ctrl = _menuController;
      if (ctrl == null) return;
      if (_overButton || _overMenu) return;
      _closeMenu();
    });
  }

  CustomHoverSelectMenuItem<T>? _selectedItem() {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedItem();
    final customColors = theme.extension<CustomColors>();
    final bgColor =
        customColors?.mainContentBgColor ?? theme.colorScheme.surface;
    final frameColor = theme.dividerColor;
    const menuRadius = 10.0;
    final buttonRadius = widget.radius;
    final buttonInnerRadius = buttonRadius > 1 ? buttonRadius - 1 : 0.0;
    final isHoverMode = widget.triggerMode == CustomHoverMenuTriggerMode.hover;

    final menuItems = widget.items
        .map((item) {
          final isSelected = item.value == widget.value;
          return MenuItemButton(
            onPressed: item.enabled
                ? () {
                    widget.onSelected(item.value);
                    _closeMenu();
                  }
                : null,
            leadingIcon: Icon(item.icon, size: widget.itemIconSize),
            trailingIcon: widget.showSelectedCheck && isSelected
                ? const Icon(Icons.check, size: 18)
                : null,
            child: Text(item.label),
          );
        })
        .toList(growable: false);

    final menuBody = CustomInsetBorderShell(
      radius: menuRadius,
      borderColor: frameColor,
      backgroundColor: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: menuItems,
      ),
    );

    final menuChildren = [
      MouseRegion(
        onEnter: (_) {
          _overMenu = true;
          _closeTimer?.cancel();
        },
        onExit: (_) {
          _overMenu = false;
          if (isHoverMode) {
            _scheduleClose();
          }
        },
        child: menuBody,
      ),
    ];

    return MenuAnchor(
      alignmentOffset: widget.menuOffset,
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(menuRadius),
          ),
        ),
      ),
      menuChildren: menuChildren,
      builder: (context, menuController, child) {
        _menuController = menuController;

        final button = CustomInsetBorderShell(
          radius: buttonRadius,
          borderColor: frameColor,
          backgroundColor: bgColor,
          child: TextButton(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.hovered)
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              backgroundColor: WidgetStatePropertyAll(bgColor),
              minimumSize: WidgetStatePropertyAll(Size(0, widget.height)),
              visualDensity: const VisualDensity(
                horizontal: -2,
                vertical: -2,
              ),
              padding: WidgetStatePropertyAll(widget.buttonPadding),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(buttonInnerRadius),
                ),
              ),
            ),
            onPressed: () {
              if (_isOpen) {
                _closeMenu();
              } else {
                // 延迟到下一帧，避免与 MenuAnchor 的焦点/手势处理冲突
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _openMenu(menuController);
                  }
                });
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected?.icon ?? widget.buttonIcon,
                  size: widget.buttonIconSize,
                ),
                const SizedBox(width: 6),
                Text(selected?.label ?? widget.value.toString()),
              ],
            ),
          ),
        );

        if (isHoverMode) {
          return MouseRegion(
            onEnter: (_) {
              _overButton = true;
              _closeTimer?.cancel();
              _openMenu(menuController);
            },
            onExit: (_) {
              _overButton = false;
              _scheduleClose();
            },
            child: button,
          );
        }

        return button;
      },
    );
  }
}
