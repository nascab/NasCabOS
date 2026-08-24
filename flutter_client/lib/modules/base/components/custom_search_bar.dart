import 'package:flutter/material.dart';

/// 通用搜索框组件（带圆角与占位符）
class CustomSearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  final double height;
  final bool isPill;
  const CustomSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.controller,
    this.height = 32,
    this.isPill = false,
  });

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  late TextEditingController _ctrl;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(covariant CustomSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onTextChange);
    if (_ownsController) {
      _ctrl.removeListener(_onTextChange);
      _ctrl.dispose();
    }
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChange);
  }

  void _onTextChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChange);
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.isPill ? widget.height / 2 : 10.0;
    return Container(
      height: widget.height.toDouble(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        // color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18),
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 0,
                ),
                filled: true,
                fillColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                hintText: widget.hintText,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
              cursorColor: theme.colorScheme.primary,
              onChanged: widget.onChanged,
            ),
          ),
          if ((_ctrl.text).isNotEmpty)
            InkWell(
              onTap: () {
                _ctrl.clear();
                widget.onClear?.call();
              },
              child: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}
