import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';

class PcWindowSpec {
  final String windowId;
  final WidgetBuilder viewBuilder;
  final String? title;
  final String? titleTooltip;
  final String? helpText;
  final Widget? icon;
  final bool showTitle;
  final bool resizable;
  final bool maximizable;
  final bool minimizable;
  final Size? minSize;
  final Size? initialSize;
  final Offset? initialPosition;

  const PcWindowSpec({
    required this.windowId,
    required this.viewBuilder,
    this.title,
    this.titleTooltip,
    this.helpText,
    this.icon,
    this.showTitle = true,
    this.resizable = true,
    this.maximizable = true,
    this.minimizable = true,
    this.minSize,
    this.initialSize,
    this.initialPosition,
  });
}

class PcWindowManager extends GetxController {
  static PcWindowManager get instance => Get.find<PcWindowManager>();

  final RxList<String> _opened = <String>[].obs;
  final RxList<String> _minimized = <String>[].obs;
  final RxList<String> _dock = <String>[].obs;
  final RxString _topmost = ''.obs;

  final RxMap<String, PcWindowSpec> _specs = <String, PcWindowSpec>{}.obs;
  final RxMap<String, bool> _maxMap = <String, bool>{}.obs;
  final RxMap<String, Offset> _posMap = <String, Offset>{}.obs;
  final RxMap<String, Size> _sizeMap = <String, Size>{}.obs;
  final Rxn<Size> _virtualDeskSize = Rxn<Size>();

  double dockOuterWidthPc = 55.0;

  double defaultWindowX = 120.0;
  double defaultWindowY = 120.0;
  double defaultWindowWidth = 800.0;
  double defaultWindowHeight = 600.0;

  @override
  void onInit() {
    super.onInit();
    _loadWindowStates();
  }

  List<String> get openedWindowIds => _opened;
  List<String> get minimizedWindowIds => _minimized;
  List<String> get dockWindowIds => _dock;
  String get topmostWindowId => _topmost.value;

  PcWindowSpec? specOf(String windowId) => _specs[windowId];
  String? titleOf(String windowId) => _specs[windowId]?.title;
  String? titleTooltipOf(String windowId) => _specs[windowId]?.titleTooltip;
  String? helpTextOf(String windowId) => _specs[windowId]?.helpText;
  Widget? iconOf(String windowId) => _specs[windowId]?.icon;
  bool showTitleOf(String windowId) => _specs[windowId]?.showTitle != false;
  WidgetBuilder? viewBuilderOf(String windowId) =>
      _specs[windowId]?.viewBuilder;

  bool isMaximized(String windowId) => _maxMap[windowId] == true;
  bool isResizable(String windowId) => _specs[windowId]?.resizable != false;
  bool isMaximizable(String windowId) => _specs[windowId]?.maximizable != false;
  bool isMinimizable(String windowId) => _specs[windowId]?.minimizable != false;
  Size? minSizeOf(String windowId) => _specs[windowId]?.minSize;

  Offset? windowPosition(String windowId) => _posMap[windowId];
  Size? windowSize(String windowId) => _sizeMap[windowId];

  Size? get virtualDeskSize => _virtualDeskSize.value;

  void setVirtualDeskSize(Size size) {
    if (_virtualDeskSize.value == size) return;
    _virtualDeskSize.value = size;
  }

  Rect getDeskRect() {
    final ctx = Get.context;
    final virtualSize = _virtualDeskSize.value;
    if (virtualSize == null && ctx == null) {
      return Rect.fromLTWH(dockOuterWidthPc, 0, 0, 0);
    }
    final size = virtualSize ?? MediaQuery.of(ctx!).size;
    return Rect.fromLTWH(
      dockOuterWidthPc,
      0,
      (size.width - dockOuterWidthPc).clamp(0.0, size.width),
      size.height,
    );
  }

  Offset getDefaultWindowPos(String windowId) {
    final desktopRect = getDeskRect();
    final safeX = (defaultWindowX + desktopRect.left).clamp(
      desktopRect.left,
      desktopRect.right,
    );
    final safeY = defaultWindowY.clamp(desktopRect.top, desktopRect.bottom);
    return Offset(safeX, safeY);
  }

  Size getDefaultWindowSize(String windowId) {
    return Size(defaultWindowWidth, defaultWindowHeight);
  }

  Offset getWindowPos(String windowId) {
    if (isMaximized(windowId)) return getDeskRect().topLeft;
    return windowPosition(windowId) ?? getDefaultWindowPos(windowId);
  }

  Size getWindowSize(String windowId) {
    final minSize = minSizeOf(windowId);
    if (isMaximized(windowId)) {
      final desktopSize = getDeskRect().size;
      if (minSize == null) return desktopSize;
      final w = desktopSize.width < minSize.width
          ? minSize.width
          : desktopSize.width;
      final h = desktopSize.height < minSize.height
          ? minSize.height
          : desktopSize.height;
      return Size(w, h);
    }
    final raw = windowSize(windowId) ?? getDefaultWindowSize(windowId);
    if (minSize == null) return raw;
    return Size(
      raw.width < minSize.width ? minSize.width : raw.width,
      raw.height < minSize.height ? minSize.height : raw.height,
    );
  }

  void openApp({
    required String windowId,
    required WidgetBuilder viewBuilder,
    String? title,
    String? titleTooltip,
    String? helpText,
    Widget? icon,
    bool showTitle = true,
    bool maximize = false,
    bool resizable = true,
    bool maximizable = true,
    bool minimizable = true,
    Size? minSize,
    Size? initialSize,
    Offset? initialPosition,
  }) {
    final resolvedMinSize = minSize ?? const Size(600, 500);
    final spec = PcWindowSpec(
      windowId: windowId,
      viewBuilder: viewBuilder,
      title: title,
      titleTooltip: titleTooltip,
      helpText: helpText,
      icon: icon,
      showTitle: showTitle,
      resizable: resizable,
      maximizable: maximizable,
      minimizable: minimizable,
      minSize: resolvedMinSize,
      initialSize: initialSize,
      initialPosition: initialPosition,
    );
    _specs[windowId] = spec;

    if (_opened.contains(windowId)) {
      _minimized.remove(windowId);
      focusWindow(windowId);
    } else {
      _opened.add(windowId);
      if (!_maxMap.containsKey(windowId)) {
        _maxMap[windowId] = maximize;
      } else if (maximize) {
        _maxMap[windowId] = true;
      }

      _posMap[windowId] =
          _posMap[windowId] ??
          (initialPosition ?? getDefaultWindowPos(windowId));
      _sizeMap[windowId] =
          _sizeMap[windowId] ?? (initialSize ?? getDefaultWindowSize(windowId));
      _persistWindowState(windowId);
      _updateTopmostWindow();
    }

    if (icon != null) {
      if (!_dock.contains(windowId)) {
        _dock.add(windowId);
      }
    } else {
      _dock.remove(windowId);
    }

    if (maximize) {
      _maxMap[windowId] = true;
      focusWindow(windowId);
    }
  }

  void closeWindow(String windowId) {
    _opened.remove(windowId);
    _minimized.remove(windowId);
    _dock.remove(windowId);
    _maxMap.remove(windowId);
    _specs.remove(windowId);
    _updateTopmostWindow();
  }

  void minimizeWindow(String windowId) {
    if (!_opened.contains(windowId)) return;
    if (!isMinimizable(windowId)) return;
    if (!_minimized.contains(windowId)) {
      _minimized.add(windowId);
      _updateTopmostWindow();
    }
  }

  void restoreWindow(String windowId) {
    _minimized.remove(windowId);
    focusWindow(windowId);
    _updateTopmostWindow();
  }

  void toggleMaximize(String windowId) {
    if (!_opened.contains(windowId)) return;
    if (!isMaximizable(windowId)) return;
    final toMax = !(_maxMap[windowId] == true);
    _maxMap[windowId] = toMax;
    focusWindow(windowId);
    _updateTopmostWindow();
  }

  void focusWindow(String windowId) {
    if (!_opened.contains(windowId)) return;
    if (_opened.isNotEmpty && _opened.last == windowId) return;
    _opened.remove(windowId);
    _opened.add(windowId);
    _updateTopmostWindow();
  }

  void setLastPosition(String windowId, Offset pos) {
    _posMap[windowId] = pos;
    _persistWindowState(windowId);
  }

  void setLastSize(String windowId, Size size) {
    final minSize = minSizeOf(windowId);
    _sizeMap[windowId] = minSize == null
        ? size
        : Size(
            size.width < minSize.width ? minSize.width : size.width,
            size.height < minSize.height ? minSize.height : size.height,
          );
    _persistWindowState(windowId);
  }

  void _updateTopmostWindow() {
    for (int i = _opened.length - 1; i >= 0; i--) {
      final id = _opened[i];
      if (!_minimized.contains(id)) {
        _topmost.value = id;
        return;
      }
    }
    _topmost.value = '';
  }

  void _loadWindowStates() {
    final data = CacheManager().getJson(CacheKeys.windowStates);
    if (data is Map) {
      data.forEach((key, value) {
        if (value is Map) {
          final x = value['x'];
          final y = value['y'];
          final w = value['w'];
          final h = value['h'];
          if (x is num && y is num) {
            _posMap[key.toString()] = Offset(x.toDouble(), y.toDouble());
          }
          if (w is num && h is num) {
            _sizeMap[key.toString()] = Size(w.toDouble(), h.toDouble());
          }
        }
      });
    }
  }

  void _persistWindowState(String windowId) {
    final map = <String, dynamic>{};
    final existing = CacheManager().getJson(CacheKeys.windowStates);
    if (existing is Map) {
      existing.forEach((k, v) {
        map[k.toString()] = v;
      });
    }
    final pos = _posMap[windowId] ?? getDefaultWindowPos(windowId);
    final size = _sizeMap[windowId] ?? getDefaultWindowSize(windowId);
    map[windowId] = {
      'x': pos.dx,
      'y': pos.dy,
      'w': size.width,
      'h': size.height,
    };
    CacheManager().setJson(CacheKeys.windowStates, map);
  }
}
