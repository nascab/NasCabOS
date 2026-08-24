import 'package:flutter/material.dart';
import '../../../core/theme/custom_colors.dart';
import '../../../../../utils/device_utils.dart';

/// 带边框的图标按钮组件
/// 支持 tooltip、hover 状态反馈（背景色变化）、点击回调和禁用状态
class CustomBorderedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final double borderRadius;
  final Color? borderColor;
  final Color? iconColor;
  final Color? hoverColor;
  final Color? backgroundColor;
  final bool enabled;
  final bool active;

  const CustomBorderedIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 32,
    this.iconSize = 16,
    this.borderRadius = 10,
    this.borderColor,
    this.iconColor,
    this.hoverColor,
    this.backgroundColor,
    this.enabled = true,
    this.active = false,
  });

  @override
  State<CustomBorderedIconButton> createState() =>
      _CustomBorderedIconButtonState();
}

class _CustomBorderedIconButtonState extends State<CustomBorderedIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isApp = DeviceUtils.isMobile || DeviceUtils.isPhone(context);
    double size = widget.size;
    double iconSize = widget.iconSize;
    //app上默认大一些
    if (isApp) size += 4;
    if (isApp) iconSize += 2;
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final defaultBgColor = null;
    final activeBorderColor = theme.colorScheme.primary;
    final activeIconColor = theme.colorScheme.primary;
    final activeBgColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    final borderColor = widget.active
        ? (widget.borderColor ?? activeBorderColor)
        : (widget.borderColor ?? theme.dividerColor);
    final hoverColor =
        widget.hoverColor ?? theme.colorScheme.primary.withValues(alpha: 0.08);
    final disabledColor = theme.disabledColor;

    final inactiveBg = widget.backgroundColor ?? defaultBgColor;
    final defaultBg = widget.active
        ? (widget.backgroundColor ?? activeBgColor)
        : inactiveBg;
    final bgColor = _hovered && widget.enabled ? hoverColor : defaultBg;

    final effectiveBorderColor = widget.enabled ? borderColor : disabledColor;
    final effectiveIconColor = widget.enabled
        ? (widget.active
              ? (widget.iconColor ?? activeIconColor)
              : widget.iconColor)
        : disabledColor;

    final child = InkWell(
      onTap: widget.enabled ? widget.onTap : null,
      onHover: widget.enabled
          ? (hovered) {
              setState(() => _hovered = hovered);
            }
          : null,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      hoverColor: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: size,
        width: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: effectiveBorderColor),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: Icon(widget.icon, size: iconSize, color: effectiveIconColor),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: child);
    }

    return child;
  }
}
