import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../pc_home_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../base/components/custom_inset_border_shell.dart';

class PcWindowScope extends InheritedWidget {
  final String windowId;

  const PcWindowScope({
    super.key,
    required this.windowId,
    required super.child,
  });

  static PcWindowScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PcWindowScope>();
  }

  @override
  bool updateShouldNotify(PcWindowScope oldWidget) =>
      windowId != oldWidget.windowId;
}

class PcAppWindow extends StatefulWidget {
  final String windowId;
  final WidgetBuilder viewBuilder;
  final String? title;
  final bool showTitle;
  const PcAppWindow({
    super.key,
    required this.windowId,
    required this.viewBuilder,
    this.title,
    this.showTitle = true,
  });

  static const double titleBarHeight = 40;
  static const double _topResizeStripHeight = 4;

  @override
  State<PcAppWindow> createState() => _PcAppWindowState();
}

class _PcAppWindowState extends State<PcAppWindow> {
  /// 只创建一次，双击检测和内容可交互性探测复用
  final GlobalKey _contentKey = GlobalKey();

  /// 拖拽开始时清除内容层在命中测试缓存中的 entry
  final GlobalKey _passthroughKey = GlobalKey();

  void _onDragStateChanged(bool isDragging) {
    if (isDragging) {
      final ro =
          _passthroughKey.currentContext?.findRenderObject()
              as _RenderContentPassthrough?;
      // 将缓存的 HitTestResult 中内容 entry 替换为 no-op，
      // 后续 pointer move 复用缓存时不会再派发给内容层
      ro?.clearContentEntries();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal = widget.windowId == 'terminal';
    final isGallery = widget.windowId == 'image_view';
    final isMovie = widget.windowId == 'movie';
    if (isTerminal || isGallery) {
      return Theme(
        data: darkTheme,
        child: Builder(builder: (context) => _buildWindow(context)),
      );
    }
    return _buildWindow(context);
  }

  Widget _buildWindow(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final theme = Theme.of(context);
    final isVideoPlayer = widget.windowId == 'video_player';
    final canResize = ctrl.windowCanResize(widget.windowId);
    const outerRadius = 16.0;
    final themeBackgroundColor = isVideoPlayer
        ? Colors.black
        : theme.scaffoldBackgroundColor;
    final isDark = theme.brightness == Brightness.dark;
    final frameColor = isDark
        ? const Color(0xFF3A3A3A).withValues(alpha: 0.4)
        : const Color(0xFFE0E0E0).withValues(alpha: 0.3);

    final appContent = PcWindowScope(
      windowId: widget.windowId,
      child: widget.viewBuilder(context),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerRadius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(outerRadius),
        clipBehavior: Clip.antiAlias,
        child: CustomInsetBorderShell(
          radius: outerRadius,
          borderWidth: 0.5,
          borderColor: frameColor,
          backgroundColor: themeBackgroundColor,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => ctrl.focusWindow(widget.windowId),
            child: Stack(
              children: [
                // 底层：拖拽区 — pointer down 时探测内容有无纯 tap 组件，有则跳过拖拽
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: PcAppWindow.titleBarHeight,
                  child: _DragArea(
                    windowId: widget.windowId,
                    checkInteractive: _hasInteractiveContentAt,
                    onDragStateChanged: _onDragStateChanged,
                  ),
                ),
                // 中层：内容（hitTest 永远返回 false，让 Stack 继续往下遍历）
                Positioned.fill(
                  child: _ContentHitPassthrough(
                    key: _passthroughKey,
                    child: Builder(
                      key: _contentKey,
                      builder: (_) => appContent,
                    ),
                  ),
                ),
                // 顶层：红绿灯按钮
                Positioned(
                  left: 12,
                  top:
                      (PcAppWindow.titleBarHeight -
                          _TrafficLightButtonsState._dotSize) /
                      2,
                  child: _TrafficLightButtons(
                    windowId: widget.windowId,
                    canMinimize: ctrl.windowCanMinimize(widget.windowId),
                    canMaximize: ctrl.windowCanMaximize(widget.windowId),
                  ),
                ),
                if (canResize)
                  Positioned(
                    right: 1.6,
                    top: 1.6,
                    child: Tooltip(
                      message: '',
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Image.asset(
                          'assets/icons/home/window_right_corner.png',
                          width: 16,
                          height: 16,
                          color:
                              (isVideoPlayer
                                      ? Colors.white
                                      : theme.colorScheme.onSurface)
                                  .withValues(alpha: 0.5),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                if (canResize)
                  Positioned(
                    left: 1.6,
                    bottom: 1.6,
                    child: Tooltip(
                      message: '',
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Image.asset(
                          'assets/icons/home/window_left_corner.png',
                          width: 16,
                          height: 16,
                          color:
                              (isVideoPlayer
                                      ? Colors.white
                                      : theme.colorScheme.onSurface)
                                  .withValues(alpha: 0.5),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                if (canResize)
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: PcAppWindow._topResizeStripHeight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 探测内容层 [localPosition] 是否有交互组件（按钮等）。
  ///
  /// 匹配两类 [RenderPointerListener]：
  /// 1. 明确设置了 onPointerUp 的 Listener（原始逻辑，保留兼容）
  /// 2. 仅设置了 onPointerDown（GestureDetector 按钮），但限定其 RenderBox
  ///    尺寸必须较小（<=250），以排除大面积容器如 Scrollable/RawGestureDetector、
  ///    悬停包裹组件等。容器级的 RenderPointerListener 覆盖整个内容区域，
  ///    不应阻止标题栏的拖拽和双击行为。
  bool _hasInteractiveContentAt(Offset localPosition) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;

    final result = BoxHitTestResult();
    if (!box.hitTest(result, position: localPosition)) return false;

    return result.path.any((e) {
      if (e.target is! RenderPointerListener) return false;
      final l = e.target as RenderPointerListener;
      if (l.onPointerDown == null || l.onPointerMove != null) return false;

      // 明确设置了 onPointerUp → 肯定是有意处理 tap
      if (l.onPointerUp != null) return true;

      // 仅 onPointerDown（GestureDetector 常见模式）：检查尺寸，
      // 大面积容器（如 ScrollView 内部的 RawGestureDetector）跳过
      final rb = l as RenderBox;
      return rb.size.width <= 250 && rb.size.height <= 250;
    });
  }
}

/// 包裹内容层，hitTest 永远返回 false。
/// 这样 Stack 会继续遍历到底层的拖拽区，让内容可点击组件优先响应，
/// 未消费的事件自然落到拖拽区。
/// 同时记录内容 entry 在 HitTestResult 中的位置，
/// 拖拽开始时通过 [clearContentEntries] 从缓存结果中剔除，
/// 避免 pointer move 复用缓存时内容响应事件。
class _ContentHitPassthrough extends SingleChildRenderObjectWidget {
  const _ContentHitPassthrough({super.key, required super.child});

  @override
  _RenderContentPassthrough createRenderObject(BuildContext context) =>
      _RenderContentPassthrough();
}

class _RenderContentPassthrough extends RenderProxyBox {
  BoxHitTestResult? _lastResult;
  int _contentEntryStart = -1;
  int _contentEntryEnd = -1;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      _contentEntryStart = result.path.length;
      child!.hitTest(result, position: position);
      _contentEntryEnd = result.path.length;
      _lastResult = result;
    }
    return false;
  }

  /// 将缓存的 HitTestResult 中内容层 entry 原地替换为 no-op，
  /// 不改变列表结构，避免 ConcurrentModificationError。
  /// Flutter pointer move 复用 pointer down 的命中测试结果，
  /// 拖拽开始时调用此方法，后续 move 事件将不再派发给内容。
  void clearContentEntries() {
    if (_lastResult != null && _contentEntryStart >= 0) {
      final path = _lastResult!.path as List<HitTestEntry>;
      for (
        int i = _contentEntryStart;
        i < _contentEntryEnd && i < path.length;
        i++
      ) {
        // 替换为自身，RenderObject 默认 handleEvent 是 no-op
        path[i] = BoxHitTestEntry(this, Offset.zero);
      }
      _contentEntryStart = -1;
      _contentEntryEnd = -1;
      _lastResult = null;
    }
  }
}

/// 标题栏拖拽区。Pointer down 时先通过 [checkInteractive] 探测内容层
/// 是否有纯 tap 组件，有则跳过拖拽（按钮即时响应）；
/// 没有才启动手动拖拽追踪。同时内置双击最大化检测。
class _DragArea extends StatefulWidget {
  final String windowId;
  final bool Function(Offset localPosition) checkInteractive;
  final ValueChanged<bool> onDragStateChanged;

  const _DragArea({
    required this.windowId,
    required this.checkInteractive,
    required this.onDragStateChanged,
  });

  @override
  State<_DragArea> createState() => _DragAreaState();
}

class _DragAreaState extends State<_DragArea> {
  bool _isDragging = false;
  Offset? _dragOrigin;

  // 双击检测
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  static const _doubleTapWindow = Duration(milliseconds: 300);
  static const _doubleTapDistance = 20.0;

  void _handlePointerDown(PointerDownEvent event) {
    final ctrl = PcHomeController.instance;
    ctrl.focusWindow(widget.windowId);

    // 内容层该位置有纯 tap 按钮 → 不启动拖拽，让它优先响应
    if (widget.checkInteractive(event.localPosition)) return;

    // 双击检测
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < _doubleTapWindow &&
        (_lastTapPosition! - event.localPosition).distance <
            _doubleTapDistance) {
      _lastTapTime = null;
      if (ctrl.windowCanMaximize(widget.windowId)) {
        ctrl.maximizeApp(widget.windowId);
      }
      return;
    }
    _lastTapTime = now;
    _lastTapPosition = event.localPosition;

    _isDragging = true;
    _dragOrigin = event.position;
    widget.onDragStateChanged(true);
  }

  void _stopDragging() {
    _isDragging = false;
    _dragOrigin = null;
    widget.onDragStateChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: (event) {
        if (!_isDragging || _dragOrigin == null) return;
        if (ctrl.isMaximized(widget.windowId)) return;
        final delta = event.position - _dragOrigin!;
        final current =
            ctrl.windowPosition(widget.windowId) ??
            ctrl.getWindowPos(widget.windowId);
        ctrl.setLastPosition(widget.windowId, current + delta);
        _dragOrigin = event.position;
      },
      onPointerUp: (_) => _stopDragging(),
      onPointerCancel: (_) => _stopDragging(),
      child: const SizedBox.expand(),
    );
  }
}

class _TrafficLightButtons extends StatefulWidget {
  final String windowId;
  final bool canMinimize;
  final bool canMaximize;

  const _TrafficLightButtons({
    required this.windowId,
    required this.canMinimize,
    required this.canMaximize,
  });

  @override
  State<_TrafficLightButtons> createState() => _TrafficLightButtonsState();
}

class _TrafficLightButtonsState extends State<_TrafficLightButtons> {
  bool _isHovering = false;

  static const double _dotSize = 12.0;
  static const double _spacing = 8.0;
  static const double _iconSize = 9.0;

  bool get _isFocused =>
      PcHomeController.instance.topmostApp == widget.windowId;

  Color _dotColor(int index) {
    if (!_isFocused) {
      return const Color(0xFF7A7A7A);
    }
    switch (index) {
      case 0:
        return const Color(0xFFFF5F57); // red - close
      case 1:
        return const Color(0xFFFFBD2E); // yellow - minimize
      case 2:
        return const Color(0xFF28CA41); // green - maximize
      default:
        return Colors.grey;
    }
  }

  Widget _buildDot(int index, VoidCallback? onTap, IconData icon) {
    final dotColor = _dotColor(index);
    final showIcon = _isHovering && _isFocused;

    return GestureDetector(
      onTap: () {
        PcHomeController.instance.focusWindow(widget.windowId);
        onTap?.call();
      },
      child: Container(
        width: _dotSize,
        height: _dotSize,
        decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        alignment: Alignment.center,
        child: showIcon
            ? Text(
                String.fromCharCode(icon.codePoint),
                style: TextStyle(
                  fontSize: _iconSize,
                  fontWeight: FontWeight.w900,
                  color: const Color(0x99000000),
                  fontFamily: 'MaterialIcons',
                  height: 1.0,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PcHomeController.instance;
    final isMaximized = ctrl.isMaximized(widget.windowId);
    final maximizeIcon = widget.canMaximize && isMaximized
        ? Icons.fullscreen_exit
        : Icons.open_in_full;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDot(0, () => ctrl.closeApp(widget.windowId), Icons.close),
          SizedBox(width: _spacing),
          _buildDot(
            1,
            widget.canMinimize ? () => ctrl.minimizeApp(widget.windowId) : null,
            Icons.remove,
          ),
          SizedBox(width: _spacing),
          _buildDot(
            2,
            widget.canMaximize ? () => ctrl.maximizeApp(widget.windowId) : null,
            maximizeIcon,
          ),
        ],
      ),
    );
  }
}
