import 'package:flutter/material.dart';

class AppCustomSearch extends StatefulWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final double height;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;
  const AppCustomSearch({
    super.key,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.controller,
    this.focusNode,
    this.height = 38,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 1,
  });

  @override
  State<AppCustomSearch> createState() => _AppCustomSearchState();
}

class _AppCustomSearchState extends State<AppCustomSearch> {
  late TextEditingController _ctrl;
  late bool _ownsController;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChange);
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(covariant AppCustomSearch oldWidget) {
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

    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
    }
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
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.height / 2;
    final bg = theme.colorScheme.surfaceContainerHighest;
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: widget.showBorder
            ? Border.all(
                color: widget.borderColor ?? theme.dividerColor,
                width: widget.borderWidth,
              )
            : null,
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              readOnly: widget.readOnly,
              onTap: widget.onTap,
              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
              },
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
              style: theme.textTheme.bodyMedium,
              cursorColor: theme.colorScheme.primary,
              onChanged: widget.onChanged,
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            InkWell(
              onTap: () {
                _ctrl.clear();
                widget.onClear?.call();
              },
              child: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}
