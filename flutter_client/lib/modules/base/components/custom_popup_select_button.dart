import 'package:flutter/material.dart';
import '../../../utils/popup_menu_util.dart';
import 'custom_bordered_icon_button.dart';

/// 下拉弹出菜单的选择项
class CustomPopupSelectItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const CustomPopupSelectItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// 点击后弹出下拉菜单的选择按钮组件
///
/// 基于 [CustomBorderedIconButton]，点击后在按钮正下方弹出菜单供选择。
/// - 当 [value] != [defaultValue] 时按钮显示 active 高亮状态
/// - 菜单中当前选中项前显示对勾图标
/// - 菜单项可配置图标（[CustomPopupSelectItem.icon]）
///
/// 通常配合 Obx 使用，将 observable 值传入 [value]：
/// ```dart
/// Obx(() => CustomPopupSelectButton<String>(
///   value: controller.currentFilter.value,
///   defaultValue: 'all',
///   items: [...],
///   onSelected: controller.setFilter,
/// ))
/// ```
class CustomPopupSelectButton<T> extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final T value;
  final List<CustomPopupSelectItem<T>> items;
  final ValueChanged<T> onSelected;
  final T? defaultValue;
  final double size;
  final double iconSize;
  final double borderRadius;
  final Color? borderColor;
  final Color? iconColor;

  const CustomPopupSelectButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.value,
    required this.items,
    required this.onSelected,
    this.defaultValue,
    this.size = 32,
    this.iconSize = 16,
    this.borderRadius = 10,
    this.borderColor,
    this.iconColor,
  });

  @override
  State<CustomPopupSelectButton<T>> createState() =>
      _CustomPopupSelectButtonState<T>();
}

class _CustomPopupSelectButtonState<T>
    extends State<CustomPopupSelectButton<T>> {
  final _buttonKey = GlobalKey();

  bool get _isActive {
    if (widget.defaultValue == null) return false;
    return widget.value != widget.defaultValue;
  }

  @override
  Widget build(BuildContext context) {
    return CustomBorderedIconButton(
      key: _buttonKey,
      icon: widget.icon,
      tooltip: widget.tooltip,
      active: _isActive,
      size: widget.size,
      iconSize: widget.iconSize,
      borderRadius: widget.borderRadius,
      borderColor: widget.borderColor,
      iconColor: widget.iconColor,
      onTap: () async {
        final result = await PopupMenuUtil.showBelowButton<T>(
          context: context,
          buttonKey: _buttonKey,
          items: widget.items.map((item) {
            final selected = item.value == widget.value;
            return PopupMenuItem<T>(
              value: item.value,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: selected ? const Icon(Icons.check, size: 18) : null,
                  ),
                  if (item.icon != null) ...[
                    Icon(item.icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(item.label),
                ],
              ),
            );
          }).toList(),
        );
        if (result != null) {
          widget.onSelected(result);
        }
      },
    );
  }
}
