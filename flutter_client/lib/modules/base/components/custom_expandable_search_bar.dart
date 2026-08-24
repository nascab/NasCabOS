import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../utils/device_utils.dart';

/// 可自动展开/收起的搜索栏组件
/// 平时只显示搜索图标，获取焦点后自动展开为完整搜索框，失去焦点且内容为空时自动收起
class CustomExpandableSearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  final double height;
  final double expandedWidth;
  final bool isPill;
  final AlignmentGeometry alignment;
  final bool defaultExpanded;
  final bool autoSearchOnChange;
  final Duration? debounceDuration;
  final ValueChanged<String>? onDebouncedChanged;

  const CustomExpandableSearchBar({
    super.key,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.controller,
    this.height = 32,
    this.expandedWidth = 180,
    this.isPill = false,
    this.alignment = Alignment.centerRight,
    this.defaultExpanded = false,
    this.autoSearchOnChange = false,
    this.debounceDuration,
    this.onDebouncedChanged,
  });

  @override
  State<CustomExpandableSearchBar> createState() =>
      _CustomExpandableSearchBarState();
}

class _CustomExpandableSearchBarState extends State<CustomExpandableSearchBar> {
  late final TextEditingController _ctrl;
  late final bool _ownsController;
  final FocusNode _focusNode = FocusNode();
  bool _isExpanded = false;
  Timer? _debounceTimer;

  static const _animDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.defaultExpanded;
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChange);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant CustomExpandableSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultExpanded != widget.defaultExpanded) {
      _isExpanded = widget.defaultExpanded;
    }
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?.removeListener(_onTextChange);
    if (_ownsController) {
      _ctrl.dispose();
    }
    _ownsController = widget.controller == null;
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ctrl.removeListener(_onTextChange);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    if (_ownsController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  void _onTextChange() {
    setState(() {});
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    if (!widget.autoSearchOnChange) return;
    _debounceTimer?.cancel();
    final dur = widget.debounceDuration ?? const Duration(milliseconds: 500);
    _debounceTimer = Timer(dur, () {
      widget.onDebouncedChanged?.call(_ctrl.text);
    });
  }

  void _onFocusChange() {
    // 默认展开模式下不自动管理焦点/收起
    if (widget.defaultExpanded) return;
    if (_focusNode.hasFocus) {
      _setExpanded(true);
    } else {
      // 失去焦点且无内容时收起
      if (_ctrl.text.isEmpty) {
        _setExpanded(false);
      }
    }
  }

  void _setExpanded(bool value) {
    // 默认展开模式下不允许收起
    if (!value && widget.defaultExpanded) return;
    if (_isExpanded == value) return;
    setState(() => _isExpanded = value);
  }

  void _expand() {
    _setExpanded(true);
    _focusNode.requestFocus();
  }

  void _handleClear() {
    _ctrl.clear();
    widget.onClear?.call();
    // _ctrl.clear() 已通过 TextField.onChanged 触发 onChanged，无需重复调用
    // 清除后若开启防抖搜索，立即触发搜索以恢复全部列表
    _debounceTimer?.cancel();
    if (widget.autoSearchOnChange) {
      final dur = widget.debounceDuration ?? const Duration(milliseconds: 500);
      _debounceTimer = Timer(dur, () {
        widget.onDebouncedChanged?.call('');
      });
    }
    if (widget.defaultExpanded) return;
    // 清空后收起
    _focusNode.unfocus();
    _setExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    final isApp = DeviceUtils.isMobile || DeviceUtils.isPhone(context);
    final theme = Theme.of(context);
    double h = widget.height;
    //app上默认大一些
    if (isApp) h += 4;
    final radius = widget.isPill ? h / 2 : 10.0;
    final decoration = BoxDecoration(
      border: Border.all(color: theme.dividerColor),
      borderRadius: BorderRadius.circular(radius),
    );

    if (widget.defaultExpanded) {
      return Container(
        width: double.infinity,
        height: h,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: _isExpanded ? _buildExpanded(theme) : _buildCollapsed(theme),
      );
    }

    return Align(
      alignment: widget.alignment,
      child: AnimatedContainer(
        duration: _animDuration,
        curve: Curves.easeInOut,
        width: _isExpanded ? widget.expandedWidth : h,
        height: h,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: _isExpanded ? _buildExpanded(theme) : _buildCollapsed(theme),
      ),
    );
  }

  Widget _buildCollapsed(ThemeData theme) {
    final radius = widget.isPill ? widget.height / 2 : 8.0;
    return InkWell(
      onTap: _expand,
      borderRadius: BorderRadius.circular(radius),
      child: Icon(Icons.search, size: widget.height * 0.6),
    );
  }

  Widget _buildExpanded(ThemeData theme) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.search, size: widget.height * 0.5),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: widget.defaultExpanded ? null : _focusNode,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
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
              onChanged: _handleChanged,
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            InkWell(
              onTap: _handleClear,
              child: Icon(Icons.close, size: widget.height * 0.5),
            ),
        ],
      ),
    );

    // 默认展开模式下直接填充父级空间，无需 OverflowBox/SizedBox 定宽
    if (widget.defaultExpanded) return child;

    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: double.infinity,
      child: SizedBox(width: widget.expandedWidth, child: child),
    );
  }
}
