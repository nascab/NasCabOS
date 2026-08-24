import 'dart:async';
import 'dart:math' as math;
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../../utils/device_utils.dart';
import '../controller/music_list_controller.dart';
import 'parts/music_list_grid.dart';
import 'parts/music_list_multi_select_bottom_bar.dart';
import 'parts/music_list_top_bar.dart';
import '../../play_service/controller/music_play_service_controller.dart';
import '../../music_main/controller/music_main_controller.dart';
import '../../sub_list/controller/music_sub_list_controller.dart';
import '../../sub_list/view/music_sub_list_overlay.dart';

class MusicListPage extends StatefulWidget {
  final String listType;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final bool isFavorite;
  final MusicListSortBy initialSortBy;
  final MusicListSortOrder initialSortOrder;
  const MusicListPage({
    super.key,
    this.listType = '',
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.isFavorite = false,
    this.initialSortBy = MusicListSortBy.mtime,
    this.initialSortOrder = MusicListSortOrder.desc,
  });

  @override
  State<MusicListPage> createState() => _MusicListPageState();
}

class _MusicListPageState extends State<MusicListPage> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;
  MusicListController? _controller;
  bool? _lastShowMultiBar;
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  bool _marqueeActive = false;
  bool _multiModeAtStart = false;
  bool _additiveAtStart = false;
  Offset _lastGridLocal = const Offset(0, 0);
  Offset? _pointerDownGridPos;
  static const double _kMarqueeThreshold = 8;

  String _rectCacheKey = '';
  List<_GridRectEntry> _gridRectCache = const [];
  List<double> _gridRectBottoms = const [];
  double _gridViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'music_list_${widget.listType}_${widget.listId ?? 0}_${widget.seriesIndexId ?? 0}_${widget.collectionId ?? 0}_${widget.isFavorite}_${widget.initialSortBy}_${widget.initialSortOrder}_${UniqueKey()}';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    if (Get.isRegistered<MusicMainController>()) {
      final mainCtrl = Get.find<MusicMainController>();
      if (mainCtrl.hidePlayerBar.value) {
        mainCtrl.hidePlayerBar.value = false;
      }
    }
    if (Get.isRegistered<MusicSubListOverlayController>()) {
      final overlayCtrl = Get.find<MusicSubListOverlayController>();
      overlayCtrl.close();
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ctrl =
        _controller ??
        (Get.isRegistered<MusicListController>(tag: _controllerTag)
            ? Get.find<MusicListController>(tag: _controllerTag)
            : null);
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    if (_dragging) {
      ctrl.updateDragSelection(
        _lastGridLocal,
        scrollOffset: _scrollController.offset,
      );
      _scheduleHitTest();
    }
    ctrl.markScrolling();
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  bool get _isAdditiveSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _scheduleHitTest() {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 60), _performHitTest);
  }

  int _lowerBoundBottom(List<double> bottoms, double value) {
    var lo = 0;
    var hi = bottoms.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (bottoms[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Set<int> _performHitTest() {
    if (!_dragging) return const {};
    final ctrl = _controller;
    if (ctrl == null) return const {};
    final rect = ctrl.selectionRectContent.value;
    if (rect == null) return const {};
    final hits = <int>{};
    final start = _lowerBoundBottom(_gridRectBottoms, rect.top);
    for (var i = start; i < _gridRectCache.length; i++) {
      final r = _gridRectCache[i].rect;
      if (r.top > rect.bottom) break;
      if (r.overlaps(rect)) hits.add(_gridRectCache[i].id);
    }
    ctrl.updateDragPreview(hits, additive: _additiveAtStart);
    return hits;
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasPixels) return;
      const edge = 30.0;
      double delta = 0.0;
      if (_lastGridLocal.dy < edge) {
        final t = (edge - _lastGridLocal.dy).clamp(0.0, edge) / edge;
        delta = -12.0 * t;
      } else {
        final distBottom = (_gridViewportHeight - _lastGridLocal.dy);
        if (distBottom < edge) {
          final t = (edge - distBottom).clamp(0.0, edge) / edge;
          delta = 12.0 * t;
        }
      }
      if (delta != 0.0) {
        final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        _scrollController.jumpTo(target);
      }
    });
  }

  void _rebuildGridRectCache({required List items, required double maxWidth}) {
    const leftPadding = 16.0;
    const rightPadding = 16.0;
    final contentWidth = math.max(0.0, maxWidth - leftPadding - rightPadding);
    const desiredWidth = 115.0;
    final crossAxisCount = (contentWidth / desiredWidth).floor().clamp(2, 10);
    const spacing = 4.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cellW = ((contentWidth - totalSpacing) / crossAxisCount)
        .floorToDouble();
    final cellH = cellW + 56.0;

    final entries = <_GridRectEntry>[];
    final bottoms = <double>[];
    for (var i = 0; i < items.length; i++) {
      final id = (items[i].id as int?) ?? 0;
      if (id <= 0) continue;
      final row = i ~/ crossAxisCount;
      final col = i % crossAxisCount;
      final x = leftPadding + col * (cellW + spacing);
      final y = row * (cellH + spacing);
      final r = Rect.fromLTWH(x, y, cellW, cellH);
      entries.add(_GridRectEntry(id: id, rect: r));
      bottoms.add(r.bottom);
    }
    _gridRectCache = entries;
    _gridRectBottoms = bottoms;
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MusicListController>(
      tag: _controllerTag,
      init: MusicListController(
        listType: widget.listType,
        listId: widget.listId,
        seriesIndexId: widget.seriesIndexId,
        collectionId: widget.collectionId,
        isFavorite: widget.isFavorite,
        initialSortBy: widget.initialSortBy,
        initialSortOrder: widget.initialSortOrder,
      ),
      builder: (ctrl) {
        _controller = ctrl;
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        final barColor =
            customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
        final overlayCtrl = Get.isRegistered<MusicSubListOverlayController>()
            ? Get.find<MusicSubListOverlayController>()
            : Get.put(MusicSubListOverlayController());

        final list = Column(
          children: [
            DeviceUtils.isPhone(context)
                ? ColoredBox(
                    color: barColor,
                    child: AppMusicListTopBar(controller: ctrl),
                  )
                : MusicListTopBar(controller: ctrl),
            Expanded(
              child: Obx(() {
                if (ctrl.loading.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                final showMultiBar = ctrl.isMultiSelectMode.value;
                if (_lastShowMultiBar != showMultiBar) {
                  _lastShowMultiBar = showMultiBar;
                  final desired = showMultiBar;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (!Get.isRegistered<MusicMainController>()) return;
                    final mainCtrl = Get.find<MusicMainController>();
                    if (mainCtrl.hidePlayerBar.value != desired) {
                      mainCtrl.hidePlayerBar.value = desired;
                    }
                  });
                }

                final playCtrl = Get.isRegistered<MusicPlayServiceController>()
                    ? Get.find<MusicPlayServiceController>()
                    : null;
                final showPlayerBar =
                    !showMultiBar &&
                    playCtrl != null &&
                    playCtrl.isReady.value &&
                    playCtrl.playlist.isNotEmpty;
                final playerExtraSpace = showPlayerBar
                    ? (112.0 + MediaQuery.of(context).padding.bottom)
                    : 0.0;

                final bottomSpace =
                    (showMultiBar ? 86.0 : 30.0) + playerExtraSpace;

                if (ctrl.items.isEmpty) {
                  return Stack(
                    children: [Center(child: CustomNoData(text: 'no_data'.tr))],
                  );
                }

                return Stack(
                  children: [
                    Scrollbar(
                      thumbVisibility: true,
                      controller: _scrollController,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final enableMarquee =
                              DeviceUtils.isDesktop ||
                              (DeviceUtils.isWeb &&
                                  DeviceUtils.isDesktopLayout(context));
                          _gridViewportHeight = constraints.maxHeight;

                          final rectKey = [
                            ctrl.items.length,
                            constraints.maxWidth.toStringAsFixed(2),
                          ].join('|');
                          if (_rectCacheKey != rectKey) {
                            _rectCacheKey = rectKey;
                            _rebuildGridRectCache(
                              items: ctrl.items,
                              maxWidth: constraints.maxWidth,
                            );
                          }

                          final scrollView = CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                sliver: MusicListGrid(controller: ctrl),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: MusicListFooter(controller: ctrl),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(height: bottomSpace),
                              ),
                            ],
                          );

                          final scrollLayer = enableMarquee
                              ? Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerDown: (e) {
                                    if (e.buttons != kPrimaryButton) return;
                                    _pointerDownGridPos = e.localPosition;
                                    _multiModeAtStart =
                                        ctrl.isMultiSelectMode.value;
                                    _additiveAtStart =
                                        _isAdditiveSelectionActive;
                                    _marqueeActive = false;
                                  },
                                  onPointerMove: (e) {
                                    if (e.buttons != kPrimaryButton) return;
                                    final origin = _pointerDownGridPos;
                                    if (origin == null) return;
                                    final local = e.localPosition;
                                    if (!_marqueeActive) {
                                      if ((local - origin).distance >
                                          _kMarqueeThreshold) {
                                        _marqueeActive = true;
                                        _dragging = true;
                                        _lastGridLocal = local;
                                        _ensureAutoTimer();
                                        _additiveAtStart =
                                            _isAdditiveSelectionActive;
                                        ctrl.startDragSelection(
                                          origin,
                                          scrollOffset:
                                              _scrollController.offset,
                                        );
                                      }
                                    }
                                    if (_marqueeActive) {
                                      _lastGridLocal = local;
                                      ctrl.updateDragSelection(
                                        local,
                                        scrollOffset: _scrollController.offset,
                                      );
                                      _scheduleHitTest();
                                    }
                                  },
                                  onPointerUp: (e) {
                                    if (_marqueeActive) {
                                      final hits = _performHitTest();
                                      _dragging = false;
                                      ctrl.finishDragSelection();
                                      ctrl.applyDragSelection(
                                        hits,
                                        multiModeAtStart: _multiModeAtStart,
                                        additive: _additiveAtStart,
                                      );
                                    } else {
                                      ctrl.finishDragSelection();
                                    }
                                    _pointerDownGridPos = null;
                                    _marqueeActive = false;
                                  },
                                  onPointerCancel: (e) {
                                    _dragging = false;
                                    ctrl.finishDragSelection();
                                    _pointerDownGridPos = null;
                                    _marqueeActive = false;
                                  },
                                  child: scrollView,
                                )
                              : scrollView;

                          return Stack(
                            children: [
                              scrollLayer,
                              if (enableMarquee)
                                Obx(() {
                                  final r = ctrl.selectionRect.value;
                                  if (r == null) return const SizedBox.shrink();
                                  return Positioned(
                                    left: r.left,
                                    top: r.top,
                                    width: r.width,
                                    height: r.height,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.15,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          );
                        },
                      ),
                    ),
                    if (showMultiBar)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: playerExtraSpace,
                        child: MusicListMultiSelectBottomBar(controller: ctrl),
                      ),
                  ],
                );
              }),
            ),
          ],
        );

        return Stack(
          children: [
            list,
            Obx(() {
              final payload = overlayCtrl.active.value;
              if (payload == null) return const SizedBox.shrink();
              return MusicSubListOverlay(
                key: ValueKey(
                  'music_sub_list_${payload.keyType}_${payload.seriesIndexId ?? 0}_${payload.name}',
                ),
                keyType: payload.keyType,
                name: payload.name,
                seriesIndexId: payload.seriesIndexId,
                onClose: overlayCtrl.close,
              );
            }),
          ],
        );
      },
    );
  }
}

class _GridRectEntry {
  final int id;
  final Rect rect;

  const _GridRectEntry({required this.id, required this.rect});
}
