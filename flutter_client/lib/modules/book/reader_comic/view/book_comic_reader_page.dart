import 'dart:async';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:extended_image/extended_image.dart';
import '../../../base/components/custom_extended_image.dart';
import '../controller/book_comic_reader_controller.dart';

class BookComicReaderPage extends StatefulWidget {
  final String fileHash;
  final String title;

  const BookComicReaderPage({
    super.key,
    required this.fileHash,
    required this.title,
  });

  @override
  State<BookComicReaderPage> createState() => _BookComicReaderPageState();
}

class _BookComicReaderPageState extends State<BookComicReaderPage> {
  late final String _tag = 'comic_reader#${widget.fileHash}';
  int _lastSettingsNonce = 0;
  final Map<int, double> _baseScales = <int, double>{};
  final Map<int, GlobalKey<ExtendedImageGestureState>> _gestureKeys =
      <int, GlobalKey<ExtendedImageGestureState>>{};

  Timer? _controlsAutoHideTimer;
  Worker? _controlsVisibleWorker;
  bool _didStartAutoHide = false;

  Offset? _pointerDownPosition;
  int? _pointerDownPointer;
  DateTime? _pointerDownTime;
  bool _pointerDownMoved = false;
  int _activePointerCount = 0;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<BookComicReaderController>(tag: _tag)) {
      Get.put(
        BookComicReaderController(
          fileHash: widget.fileHash,
          title: widget.title,
        ),
        tag: _tag,
      );
    }
    final ctrl = Get.find<BookComicReaderController>(tag: _tag);
    _controlsVisibleWorker = ever<bool>(ctrl.isControlsVisible, (visible) {
      if (!visible) {
        _cancelControlsAutoHide();
        return;
      }
      if (_didStartAutoHide) {
        _bumpControlsAutoHide(ctrl);
      }
    });
  }

  @override
  void dispose() {
    _controlsVisibleWorker?.dispose();
    _controlsVisibleWorker = null;
    _cancelControlsAutoHide();
    if (Get.isRegistered<BookComicReaderController>(tag: _tag)) {
      Get.delete<BookComicReaderController>(tag: _tag, force: true);
    }
    super.dispose();
  }

  void _cancelControlsAutoHide() {
    _controlsAutoHideTimer?.cancel();
    _controlsAutoHideTimer = null;
  }

  void _bumpControlsAutoHide(BookComicReaderController ctrl) {
    _cancelControlsAutoHide();
    _controlsAutoHideTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (!ctrl.isControlsVisible.value) return;
      ctrl.toggleControls();
    });
  }

  void _toggleControlsFromImageTap(BookComicReaderController ctrl) {
    ctrl.toggleControls();
    if (!ctrl.isControlsVisible.value) {
      _cancelControlsAutoHide();
      return;
    }
    if (_didStartAutoHide) {
      _bumpControlsAutoHide(ctrl);
    }
  }

  String _shortcutDialogTitle() {
    final raw = 'comic_reader_shortcuts'.tr;
    final idxCn = raw.indexOf('：');
    final idxEn = raw.indexOf(':');
    final idx = idxCn >= 0 ? idxCn : (idxEn >= 0 ? idxEn : -1);
    if (idx > 0) {
      return raw.substring(0, idx).trim();
    }
    return 'Shortcuts';
  }

  List<String> _shortcutLines() {
    final lang = Get.locale?.languageCode ?? 'en';
    if (lang.startsWith('zh')) {
      return [
        '←：上一页/向左',
        '→：下一页/向右',
        '↑：上一页',
        '↓：下一页',
        'PgUp：上一页',
        'PgDn：下一页',
        'Space：下一页',
        'Home：第一页',
        'End：最后一页',
        'Z：切换适应模式',
        'C：切换边距',
        'D：切换单双页布局',
        'L：从左到右',
        'R：从右到左',
        'V：垂直模式',
        'P：自动播放开关',
        'S：打开设置',
        'M：显隐菜单',
        'F：全屏开关',
        'Esc：返回',
      ];
    }
    return [
      '←: previous page / left',
      '→: next page / right',
      '↑: previous page',
      '↓: next page',
      'PgUp: previous page',
      'PgDn: next page',
      'Space: next page',
      'Home: first page',
      'End: last page',
      'Z: toggle fit mode',
      'C: cycle margin',
      'D: toggle layout',
      'L: left-to-right mode',
      'R: right-to-left mode',
      'V: vertical mode',
      'P: toggle auto play',
      'S: open settings',
      'M: toggle menu',
      'F: toggle fullscreen',
      'Esc: back',
    ];
  }

  Future<void> _showShortcutHelpDialog() async {
    final lines = _shortcutLines();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_shortcutDialogTitle()),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
  }

  void _maybeOpenSettingsSheet(BookComicReaderController ctrl) {
    final nonce = ctrl.openSettingsNonce.value;
    if (nonce == _lastSettingsNonce) return;
    _lastSettingsNonce = nonce;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showSettingsSheet(ctrl);
    });
  }

  Future<void> _showPreviewDialog(BookComicReaderController ctrl) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text('comic_reader_preview'.tr),
              leading: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        ctrl.pageIndicatorText,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.7,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: ctrl.pages.length,
                        itemBuilder: (_, index) {
                          final page = ctrl.pages[index];
                          final url = (page['url'] ?? '').toString();
                          return InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              ctrl.jumpToPageNumber(index + 1);
                            },
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CustomExtendedImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      mode: ExtendedImageMode.none,
                                      showLoading: true,
                                      borderRadius: 0,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSettingsSheet(BookComicReaderController ctrl) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Obx(() {
              final isFitWidth = ctrl.fitMode.value == ComicFitMode.fitWidth;
              return ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: Text('comic_reader_autoplay'.tr),
                    trailing: Switch(
                      value: ctrl.isAutoPlaying.value,
                      onChanged: (_) => ctrl.toggleAutoPlay(),
                    ),
                    onTap: ctrl.toggleAutoPlay,
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer),
                    title: Text('comic_reader_autoplay_interval'.tr),
                    subtitle: Text(
                      '${(ctrl.autoPlayIntervalMs.value / 1000).round()} ${'comic_reader_seconds'.tr}',
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final v = await _showNumberInputDialog(
                        title: 'comic_reader_autoplay_interval'.tr,
                        hintText: 'comic_reader_seconds'.tr,
                        initialValue: (ctrl.autoPlayIntervalMs.value / 1000)
                            .round(),
                      );
                      if (v != null) {
                        ctrl.setAutoPlayIntervalSeconds(v);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio),
                    title: Text('comic_reader_fit_mode'.tr),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<ComicFitMode>(
                        value: ctrl.fitMode.value,
                        items: [
                          DropdownMenuItem(
                            value: ComicFitMode.fitScreen,
                            child: Text('comic_reader_fit_screen'.tr),
                          ),
                          DropdownMenuItem(
                            value: ComicFitMode.fitWidth,
                            child: Text('comic_reader_fit_width'.tr),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          if (v == ctrl.fitMode.value) return;
                          ctrl.toggleFitMode();
                        },
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.space_bar),
                    title: Text('comic_reader_side_margin'.tr),
                    subtitle: isFitWidth
                        ? null
                        : Text(
                            'comic_reader_side_margin_hint'.tr,
                            style: theme.textTheme.bodySmall,
                          ),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<double>(
                        value: ctrl.sideMarginPercent.value,
                        items: const [
                          DropdownMenuItem(value: 0.0, child: Text('0%')),
                          DropdownMenuItem(value: 0.1, child: Text('10%')),
                          DropdownMenuItem(value: 0.2, child: Text('20%')),
                          DropdownMenuItem(value: 0.3, child: Text('30%')),
                          DropdownMenuItem(value: 0.4, child: Text('40%')),
                        ],
                        onChanged: isFitWidth
                            ? (v) {
                                if (v == null) return;
                                ctrl.setSideMargin(v);
                              }
                            : null,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.view_agenda),
                    title: Text('comic_reader_page_layout'.tr),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<ComicPageLayout>(
                        value: ctrl.pageLayout.value,
                        items: [
                          DropdownMenuItem(
                            value: ComicPageLayout.single,
                            child: Text('comic_reader_layout_single'.tr),
                          ),
                          DropdownMenuItem(
                            value: ComicPageLayout.double,
                            child: Text('comic_reader_layout_double'.tr),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          if (v == ctrl.pageLayout.value) return;
                          ctrl.togglePageLayout();
                        },
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text('comic_reader_reading_mode'.tr),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<ComicReadingMode>(
                        value: ctrl.readingMode.value,
                        items: [
                          DropdownMenuItem(
                            value: ComicReadingMode.ltr,
                            child: Text('comic_reader_mode_ltr'.tr),
                          ),
                          DropdownMenuItem(
                            value: ComicReadingMode.rtl,
                            child: Text('comic_reader_mode_rtl'.tr),
                          ),
                          DropdownMenuItem(
                            value: ComicReadingMode.vertical,
                            child: Text('comic_reader_mode_vertical'.tr),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          ctrl.setReadingMode(v);
                        },
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_color_fill),
                    title: Text('comic_reader_background_color'.tr),
                    trailing: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: ctrl.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: theme.dividerColor, width: 1),
                      ),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final color = await _showColorPickerDialog(
                        initial: ctrl.backgroundColor,
                      );
                      if (color != null) {
                        ctrl.setBackgroundColor(color);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_back_ios_new),
                    title: Text('comic_reader_nav_buttons'.tr),
                    trailing: Switch(
                      value: ctrl.showNavButtons.value,
                      onChanged: (_) => ctrl.toggleNavButtons(),
                    ),
                    onTap: ctrl.toggleNavButtons,
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_list_numbered),
                    title: Text('comic_reader_jump_to_page'.tr),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final result = await _showNumberInputDialog(
                        title: 'comic_reader_jump_to_page'.tr,
                        hintText: 'comic_reader_page_hint'.trParams({
                          'total': '${ctrl.totalPages}',
                        }),
                        initialValue:
                            ctrl.primaryPageIndexForSpread(ctrl.currentIndex) +
                            1,
                      );
                      if (result != null) {
                        ctrl.jumpToPageNumber(result);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: Text('comic_reader_reset_settings'.tr),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await ctrl.resetSettings();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'comic_reader_shortcuts'.tr,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
  }

  Future<int?> _showNumberInputDialog({
    required String title,
    required String hintText,
    required int initialValue,
  }) async {
    final textController = TextEditingController(text: '$initialValue');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: hintText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () {
                final raw = textController.text.trim();
                final v = int.tryParse(raw);
                Navigator.of(ctx).pop(v);
              },
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<Color?> _showColorPickerDialog({required Color initial}) async {
    final textController = TextEditingController(
      text: initial.value.toRadixString(16).padLeft(8, '0').toUpperCase(),
    );
    Color current = initial;
    final presets = [
      Colors.black,
      Colors.white,
      Colors.grey.shade900,
      Colors.grey.shade700,
      Colors.blueGrey.shade900,
      const Color(0xFF0F0F0F),
      const Color(0xFF1B263B),
      const Color(0xFF2D2A32),
    ];

    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('comic_reader_background_color'.tr),
          content: StatefulBuilder(
            builder: (ctx, setLocalState) {
              return SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in presets)
                          InkWell(
                            onTap: () {
                              setLocalState(() {
                                current = c;
                                textController.text = current.value
                                    .toRadixString(16)
                                    .padLeft(8, '0')
                                    .toUpperCase();
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(ctx).dividerColor,
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      decoration: InputDecoration(
                        labelText: 'comic_reader_color_hex'.tr,
                      ),
                      onChanged: (v) {
                        final cleaned = v.trim().replaceAll('#', '');
                        final parsed = int.tryParse(cleaned, radix: 16);
                        if (parsed == null) return;
                        if (cleaned.length == 6) {
                          setLocalState(
                            () => current = Color(0xFF000000 | parsed),
                          );
                        } else if (cleaned.length == 8) {
                          setLocalState(() => current = Color(parsed));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'comic_reader_preview'.tr,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: current,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Theme.of(ctx).dividerColor,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(current),
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
    return result;
  }

  void _resetFitWidthPositionIfNeeded(
    BookComicReaderController ctrl,
    int spreadIndex,
  ) {
    if (ctrl.fitMode.value != ComicFitMode.fitWidth) return;
    if (ctrl.spreadCount <= 0) return;
    final indices = ctrl.pageIndicesForSpread(
      spreadIndex.clamp(0, ctrl.spreadCount - 1),
    );
    final pages = indices.whereType<int>().toList();
    if (pages.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        for (final pageIndex in pages) {
          _gestureKeys[pageIndex] = GlobalKey<ExtendedImageGestureState>();
          _baseScales.remove(pageIndex);
        }
      });
    });
  }

  Widget _navButton({
    required VoidCallback onPressed,
    required IconData icon,
    double iconSize = 56,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        iconSize: iconSize,
      ),
    );
  }

  Widget _buildPageImage(BookComicReaderController ctrl, int pageIndex) {
    final page = ctrl.pages[pageIndex];
    final url = (page['url'] ?? '').toString();
    final key = _gestureKeys.putIfAbsent(
      pageIndex,
      () => GlobalKey<ExtendedImageGestureState>(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final enableFitWidth = ctrl.fitMode.value == ComicFitMode.fitWidth;
        final viewport = constraints.biggest;

        final image = CustomExtendedImage(
          imageUrl: url,
          fit: BoxFit.contain,
          mode: ExtendedImageMode.gesture,
          initGestureConfigHandler: (state) {
            double computedBase = 1.0;
            final img = state.extendedImageInfo?.image;
            if (enableFitWidth &&
                img != null &&
                viewport.width > 0 &&
                viewport.height > 0) {
              final iw = img.width.toDouble();
              final ih = img.height.toDouble();
              if (iw > 0 && ih > 0) {
                final widthScale = viewport.width / iw;
                final heightScale = viewport.height / ih;
                final containScale = widthScale < heightScale
                    ? widthScale
                    : heightScale;
                if (containScale > 0) {
                  computedBase = (widthScale / containScale).clamp(1.0, 10.0);
                }
              }
            }
            _baseScales[pageIndex] = computedBase;
            final initial = ctrl.scales[pageIndex] ?? computedBase;
            return GestureConfig(
              minScale: 0.5,
              maxScale: 10.0,
              animationMinScale: 0.5,
              animationMaxScale: 10,
              initialScale: initial,
              inPageView: true,
              initialAlignment: enableFitWidth
                  ? InitialAlignment.topCenter
                  : InitialAlignment.center,
            );
          },
          onDoubleTap: (ExtendedImageGestureState state) {
            final bs = _baseScales[pageIndex] ?? 1.0;
            ctrl.handleDoubleTapScale(pageIndex, state, baseScale: bs);
          },
          extendedImageKey: key,
          showLoading: true,
          borderRadius: 0,
        );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (signal) {
            if (signal is! PointerScrollEvent) return;
            final gestureState = key.currentState;
            if (gestureState == null) return;

            final bs = _baseScales[pageIndex] ?? 1.0;
            final cs = ctrl.scales[pageIndex] ?? bs;
            final zoomIn = signal.scrollDelta.dy < 0;
            final nextScale = (zoomIn ? cs * 1.12 : cs / 1.12).clamp(0.5, 10.0);
            gestureState.handleDoubleTap(
              scale: nextScale,
              doubleTapPosition: signal.localPosition,
            );
            ctrl.setScale(pageIndex, nextScale);
          },
          child: image,
        );
      },
    );
  }

  Widget _buildSpread(BookComicReaderController ctrl, int spreadIndex) {
    final indices = ctrl.pageIndicesForSpread(spreadIndex);
    final isFitWidth = ctrl.fitMode.value == ComicFitMode.fitWidth;
    final hPad = isFitWidth
        ? MediaQuery.of(context).size.width * ctrl.sideMarginPercent.value / 2
        : 0.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: indices.length <= 1
          ? (indices.first == null
                ? const SizedBox.shrink()
                : _buildPageImage(ctrl, indices.first!))
          : Row(
              children: indices.map((pageIndex) {
                if (pageIndex == null) {
                  return const Expanded(child: SizedBox.shrink());
                }
                return Expanded(child: _buildPageImage(ctrl, pageIndex));
              }).toList(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<BookComicReaderController>(
      tag: _tag,
      builder: (ctrl) {
        return Obx(() {
          _maybeOpenSettingsSheet(ctrl);
          final isMobile = DeviceUtils.isPhone(context);

          if (ctrl.isLoading.value) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: Center(child: Text('loading'.tr)),
            );
          }

          if (ctrl.pages.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: Center(child: Text('no_data'.tr)),
            );
          }

          if (!_didStartAutoHide) {
            _didStartAutoHide = true;
            if (ctrl.isControlsVisible.value) {
              _bumpControlsAutoHide(ctrl);
            }
          }

          return Scaffold(
            body: Stack(
              children: [
                Container(color: ctrl.backgroundColor),
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    _activePointerCount += 1;
                    if (_activePointerCount == 1) {
                      _pointerDownPosition = e.position;
                      _pointerDownPointer = e.pointer;
                      _pointerDownTime = DateTime.now();
                      _pointerDownMoved = false;
                    } else {
                      _pointerDownPointer = null;
                    }

                    if (ctrl.isControlsVisible.value) {
                      _bumpControlsAutoHide(ctrl);
                    }
                  },
                  onPointerMove: (e) {
                    final p = _pointerDownPointer;
                    final down = _pointerDownPosition;
                    if (p == null || down == null) return;
                    if (_pointerDownMoved) return;
                    if (e.pointer != p) return;
                    final d = (e.position - down).distance;
                    if (d > 10) {
                      _pointerDownMoved = true;
                    }
                  },
                  onPointerCancel: (_) {
                    if (_activePointerCount > 0) {
                      _activePointerCount -= 1;
                    }
                    _pointerDownPointer = null;
                    _pointerDownPosition = null;
                    _pointerDownTime = null;
                    _pointerDownMoved = false;
                  },
                  onPointerUp: (e) {
                    if (_activePointerCount > 0) {
                      _activePointerCount -= 1;
                    }
                    final p = _pointerDownPointer;
                    final down = _pointerDownPosition;
                    final t = _pointerDownTime;

                    _pointerDownPointer = null;
                    _pointerDownPosition = null;
                    _pointerDownTime = null;
                    final moved = _pointerDownMoved;
                    _pointerDownMoved = false;

                    if (_activePointerCount != 0) return;
                    if (p == null || down == null || t == null) return;
                    if (e.pointer != p) return;

                    final dt = DateTime.now().difference(t);
                    if (dt > const Duration(milliseconds: 250)) return;
                    final d = (e.position - down).distance;
                    if (d > 10) return;
                    if (moved) return;

                    _toggleControlsFromImageTap(ctrl);
                  },
                  child: ExtendedImageGesturePageView.builder(
                    key: ValueKey(
                      '${ctrl.fitMode.value}|${ctrl.pageLayout.value}|${ctrl.readingMode.value}|${ctrl.sideMarginPercent.value}',
                    ),
                    controller: ctrl.pageController,
                    itemCount: ctrl.spreadCount,
                    scrollDirection: ctrl.scrollAxis,
                    reverse:
                        !ctrl.isVertical &&
                        ctrl.readingMode.value == ComicReadingMode.rtl,
                    canScrollPage: ctrl.isVertical
                        ? (GestureDetails? details) => true
                        : null,
                    onPageChanged: (idx) {
                      ctrl.handleSpreadChanged(idx);
                      _resetFitWidthPositionIfNeeded(ctrl, idx);
                      if (!ctrl.isAutoPlaying.value &&
                          ctrl.isControlsVisible.value) {
                        _bumpControlsAutoHide(ctrl);
                      }
                    },
                    itemBuilder: (_, spreadIndex) {
                      return _buildSpread(ctrl, spreadIndex);
                    },
                  ),
                ),
                Obx(() {
                  if (!ctrl.showNavButtons.value) {
                    return const SizedBox.shrink();
                  }
                  if (!ctrl.isControlsVisible.value) {
                    return const SizedBox.shrink();
                  }
                  if (ctrl.isVertical) {
                    return Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _navButton(
                              onPressed: ctrl.goUpAction,
                              icon: Icons.keyboard_arrow_up,
                              iconSize: 44,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _navButton(
                              onPressed: ctrl.goDownAction,
                              icon: Icons.keyboard_arrow_down,
                              iconSize: 44,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return Stack(
                    children: [
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navButton(
                            onPressed: ctrl.goLeftAction,
                            icon: Icons.chevron_left,
                            iconSize: 72,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navButton(
                            onPressed: ctrl.goRightAction,
                            icon: Icons.chevron_right,
                            iconSize: 72,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                Obx(() {
                  if (!ctrl.isControlsVisible.value) {
                    return const SizedBox.shrink();
                  }
                  return SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: Container(
                            height: 56,
                            color: Colors.black.withOpacity(0.35),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: Material(
                            color: Colors.transparent,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'back'.tr,
                                  onPressed: () => Get.back(),
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                  ),
                                ),
                                if (!isMobile)
                                  Text(
                                    ctrl.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Material(
                            color: Colors.transparent,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: _shortcutDialogTitle(),
                                  onPressed: () async {
                                    if (ctrl.isControlsVisible.value) {
                                      _bumpControlsAutoHide(ctrl);
                                    }
                                    await _showShortcutHelpDialog();
                                  },
                                  icon: const Icon(
                                    Icons.help_outline,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'comic_reader_fullscreen'.tr,
                                  onPressed: () {
                                    if (ctrl.isControlsVisible.value) {
                                      _bumpControlsAutoHide(ctrl);
                                    }
                                    ctrl.toggleFullscreen();
                                  },
                                  icon: Obx(
                                    () => Icon(
                                      ctrl.isFullscreen.value
                                          ? Icons.fullscreen_exit_rounded
                                          : Icons.fullscreen_rounded,
                                      size: 28,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'comic_reader_autoplay'.tr,
                                  onPressed: () {
                                    if (ctrl.isControlsVisible.value) {
                                      _bumpControlsAutoHide(ctrl);
                                    }
                                    ctrl.toggleAutoPlay();
                                  },
                                  icon: Obx(
                                    () => Icon(
                                      ctrl.isAutoPlaying.value
                                          ? Icons.stop_circle_outlined
                                          : Icons.play_circle_outline,
                                      size: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'comic_reader_preview'.tr,
                                  onPressed: () async {
                                    if (ctrl.isControlsVisible.value) {
                                      _bumpControlsAutoHide(ctrl);
                                    }
                                    await _showPreviewDialog(ctrl);
                                  },
                                  icon: const Icon(
                                    Icons.grid_view,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'setting'.tr,
                                  onPressed: () async {
                                    if (ctrl.isControlsVisible.value) {
                                      _bumpControlsAutoHide(ctrl);
                                    }
                                    await _showSettingsSheet(ctrl);
                                  },
                                  icon: const Icon(
                                    Icons.settings,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ctrl.pageIndicatorText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        });
      },
    );
  }
}
