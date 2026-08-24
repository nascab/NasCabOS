import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/custom_colors.dart';
import 'custom_inset_border_shell.dart';

enum CustomHoverMenuTriggerMode {
  /// 鼠标悬停触发
  hover,

  /// 点击触发
  click,
}

/// 通用弹出菜单锚点组件。
/// 支持悬停触发和点击触发两种模式，默认点击触发。
class CustomHoverMenuAnchor extends StatefulWidget {
  final Widget child;
  final List<Widget> menuChildren;
  final Offset alignmentOffset;
  final double menuRadius;
  final double buttonRadius;
  final EdgeInsetsGeometry buttonPadding;
  final double? buttonMinimumHeight;
  final CustomHoverMenuTriggerMode triggerMode;

  const CustomHoverMenuAnchor({
    super.key,
    required this.child,
    required this.menuChildren,
    this.alignmentOffset = const Offset(0, 6),
    this.menuRadius = 10.0,
    this.buttonRadius = 10.0,
    this.buttonPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
    this.buttonMinimumHeight,
    this.triggerMode = CustomHoverMenuTriggerMode.click,
  });

  @override
  State<CustomHoverMenuAnchor> createState() => _CustomHoverMenuAnchorState();
}

class _CustomHoverMenuAnchorState extends State<CustomHoverMenuAnchor> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final bgColor =
        customColors?.mainContentBgColor ?? theme.colorScheme.surface;
    final frameColor = theme.dividerColor;
    final menuRadius = widget.menuRadius;
    final buttonRadius = widget.buttonRadius;
    final isHoverMode = widget.triggerMode == CustomHoverMenuTriggerMode.hover;

    final List<Widget> menuBodyChildren;
    if (isHoverMode) {
      menuBodyChildren = widget.menuChildren
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
    } else {
      menuBodyChildren = widget.menuChildren;
    }

    final menuBody = CustomInsetBorderShell(
      radius: menuRadius,
      borderColor: frameColor,
      backgroundColor: bgColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: menuBodyChildren,
      ),
    );

    final menuChildren = isHoverMode
        ? [menuBody]
        : [
            MouseRegion(
              onEnter: (_) {
                _overMenu = true;
                _closeTimer?.cancel();
              },
              onExit: (_) {
                _overMenu = false;
                _scheduleClose();
              },
              child: menuBody,
            ),
          ];

    return MenuAnchor(
      alignmentOffset: widget.alignmentOffset,
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
          clipChild: false,
          child: TextButton(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.hovered)
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              backgroundColor: WidgetStatePropertyAll(bgColor),
              minimumSize: widget.buttonMinimumHeight != null
                  ? WidgetStatePropertyAll(
                      Size(0, widget.buttonMinimumHeight!),
                    )
                  : null,
              visualDensity: const VisualDensity(
                horizontal: -2,
                vertical: -2,
              ),
              padding: WidgetStatePropertyAll(widget.buttonPadding),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(buttonRadius - 1),
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
            child: widget.child,
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
