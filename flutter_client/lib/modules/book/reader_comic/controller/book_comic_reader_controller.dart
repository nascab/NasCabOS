import 'dart:async';
import 'dart:convert';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/core/api/api_controller.dart';
import '../../../../utils/cache_manager.dart';
import '../service/book_comic_reader_api_service.dart';

enum ComicFitMode { fitScreen, fitWidth }

enum ComicPageLayout { single, double }

enum ComicReadingMode { ltr, rtl, vertical }

class BookComicReaderController extends GetxController {
  final String fileHash;
  final String title;

  BookComicReaderController({required this.fileHash, required this.title});

  late ExtendedPageController pageController;

  final RxList<Map<String, dynamic>> pages = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isControlsVisible = true.obs;
  final RxString errorMsg = ''.obs;

  final RxMap<int, double> scales = <int, double>{}.obs;
  final List<double> doubleTapScales = [1.0, 3.0];

  final Rx<ComicFitMode> fitMode = ComicFitMode.fitScreen.obs;
  final Rx<ComicPageLayout> pageLayout = ComicPageLayout.single.obs;
  final Rx<ComicReadingMode> readingMode = ComicReadingMode.ltr.obs;
  final RxDouble sideMarginPercent = 0.0.obs;
  final RxInt backgroundColorValue = Colors.black.value.obs;
  final RxInt autoPlayIntervalMs = 3000.obs;
  final RxBool showNavButtons = true.obs;
  final RxBool isAutoPlaying = false.obs;
  final RxBool isFullscreen = false.obs;
  final RxInt openSettingsNonce = 0.obs;
  final RxInt currentSpreadIndexRx = 0.obs;

  final BookComicReaderApiService _api = BookComicReaderApiService.instance;
  final RxnInt _initialIndex = RxnInt();

  Timer? _saveDebounce;
  Timer? _autoPlayTimer;
  int _lastKnownIndex = -1;
  int _lastSavedIndex = -1;
  bool _didInitialJump = false;

  @override
  void onInit() {
    super.onInit();
    pageController = ExtendedPageController(initialPage: 0);
    pageController.addListener(_onPageControllerChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _loadLocalSettings();
    unawaited(_initLoad());
  }

  @override
  void onClose() {
    _stopAutoPlay();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    pageController.removeListener(_onPageControllerChanged);
    pageController.dispose();
    _saveDebounce?.cancel();
    super.onClose();
  }

  Future<void> _initLoad() async {
    isLoading.value = true;
    errorMsg.value = '';
    try {
      final progress = await _api.getProgress(
        fileHash: fileHash,
        showLoading: false,
      );
      if (progress != null) {
        final raw = progress['current_page'];
        final cp = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
        if (cp >= 0) _initialIndex.value = cp;
      }

      final items = await _api.listArchiveImages(
        fileHash: fileHash,
        onlyImg: true,
        showLoading: false,
      );
      pages.assignAll(items);
      _scheduleInitialJump();
    } catch (e) {
      errorMsg.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void _scheduleInitialJump() {
    if (_didInitialJump) return;
    final target = _initialIndex.value;
    if (target == null) return;
    if (pages.isEmpty) return;
    final maxIndex = pages.length - 1;
    final clampedPageIndex = target.clamp(0, maxIndex);
    final clamped = spreadIndexForPageIndex(clampedPageIndex);

    void tryJump() {
      if (_didInitialJump) return;
      if (!pageController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tryJump());
        return;
      }
      pageController.jumpToPage(clamped);
      _didInitialJump = true;
      _lastKnownIndex = clamped;
      _lastSavedIndex = clamped;
      currentSpreadIndexRx.value = clamped;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryJump());
  }

  int get currentIndex {
    if (!pageController.hasClients) return 0;
    return pageController.page?.round() ?? 0;
  }

  int get totalPages => pages.length;
  int get spreadCount {
    if (pages.isEmpty) return 0;
    if (pageLayout.value == ComicPageLayout.double) {
      return (pages.length / 2.0).ceil();
    }
    return pages.length;
  }

  int spreadIndexForPageIndex(int pageIndex) {
    if (pageLayout.value == ComicPageLayout.double) {
      return (pageIndex / 2.0).floor();
    }
    return pageIndex;
  }

  int primaryPageIndexForSpread(int spreadIndex) {
    if (pageLayout.value == ComicPageLayout.double) {
      return (spreadIndex * 2).clamp(0, pages.length - 1);
    }
    return spreadIndex.clamp(0, pages.length - 1);
  }

  List<int?> pageIndicesForSpread(int spreadIndex) {
    if (pages.isEmpty) return const <int?>[];
    final primary = primaryPageIndexForSpread(spreadIndex);
    if (pageLayout.value == ComicPageLayout.single) {
      return <int?>[primary];
    }
    final second = primary + 1;
    final hasSecond = second >= 0 && second < pages.length;
    if (readingMode.value == ComicReadingMode.rtl) {
      return <int?>[hasSecond ? second : null, primary];
    }
    return <int?>[primary, hasSecond ? second : null];
  }

  String get pageIndicatorText {
    final spreadIdx = currentSpreadIndexRx.value.clamp(0, spreadCount - 1);
    final indices = pageIndicesForSpread(spreadIdx);
    final valid = indices.whereType<int>().toList();
    if (valid.isEmpty) return '0 / $totalPages';
    if (valid.length == 1) {
      return '${valid.first + 1} / $totalPages';
    }
    final a = valid[0] + 1;
    final b = valid[1] + 1;
    return '$a-$b / $totalPages';
  }

  void toggleControls() {
    isControlsVisible.toggle();
    _persistLocalSettings();
  }

  void previousPage() {
    final idx = currentIndex;
    if (idx <= 0) return;
    pageController.jumpToPage(idx - 1);
  }

  void nextPage() {
    final idx = currentIndex;
    if (idx >= spreadCount - 1) return;
    pageController.jumpToPage(idx + 1);
  }

  void goToFirstPage() {
    if (spreadCount <= 0) return;
    pageController.jumpToPage(0);
  }

  void goToLastPage() {
    if (spreadCount <= 0) return;
    pageController.jumpToPage(spreadCount - 1);
  }

  void toggleFitMode() {
    final keepSpreadIndex = spreadCount > 0
        ? currentIndex.clamp(0, spreadCount - 1)
        : 0;
    fitMode.value = fitMode.value == ComicFitMode.fitScreen
        ? ComicFitMode.fitWidth
        : ComicFitMode.fitScreen;
    if (fitMode.value != ComicFitMode.fitWidth) {
      sideMarginPercent.value = 0;
    }
    _scheduleRestoreSpread(keepSpreadIndex);
    _persistLocalSettings();
  }

  void toggleAutoPlay() {
    final next = !isAutoPlaying.value;
    isAutoPlaying.value = next;
    if (next) {
      _startAutoPlay();
    } else {
      _stopAutoPlay();
    }
    _persistLocalSettings();
  }

  void _startAutoPlay() {
    _stopAutoPlay();
    if (spreadCount <= 1) return;
    _autoPlayTimer = Timer.periodic(
      Duration(milliseconds: autoPlayIntervalMs.value),
      (_) {
        final idx = currentIndex;
        if (idx >= spreadCount - 1) {
          toggleAutoPlay();
          return;
        }
        nextPage();
      },
    );
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  void toggleFullscreen() {
    final next = !isFullscreen.value;
    isFullscreen.value = next;
    try {
      FullScreen.setFullScreen(next);
    } catch (_) {}
    isFullscreen.value = FullScreen.isFullScreen;
    _persistLocalSettings();
  }

  void togglePageLayout() {
    final currentPageIndex = pages.isEmpty
        ? 0
        : primaryPageIndexForSpread(currentIndex).clamp(0, pages.length - 1);
    pageLayout.value = pageLayout.value == ComicPageLayout.single
        ? ComicPageLayout.double
        : ComicPageLayout.single;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!pageController.hasClients) return;
      final spreadIdx = spreadIndexForPageIndex(currentPageIndex);
      pageController.jumpToPage(spreadIdx);
    });
    update();
    _persistLocalSettings();
  }

  void setReadingMode(ComicReadingMode mode) {
    final keepSpreadIndex = spreadCount > 0
        ? currentIndex.clamp(0, spreadCount - 1)
        : 0;
    readingMode.value = mode;
    _scheduleRestoreSpread(keepSpreadIndex);
    _persistLocalSettings();
  }

  void cycleSideMargin() {
    if (fitMode.value != ComicFitMode.fitWidth) return;
    const values = <double>[0.0, 0.1, 0.2, 0.3, 0.4];
    final current = sideMarginPercent.value;
    final idx = values.indexWhere((e) => (e - current).abs() < 0.0001);
    final nextIdx = idx < 0 ? 0 : (idx + 1) % values.length;
    sideMarginPercent.value = values[nextIdx];
    _persistLocalSettings();
  }

  void setSideMargin(double percent) {
    final keepSpreadIndex = spreadCount > 0
        ? currentIndex.clamp(0, spreadCount - 1)
        : 0;
    if (fitMode.value != ComicFitMode.fitWidth) {
      sideMarginPercent.value = 0;
    } else {
      sideMarginPercent.value = percent.clamp(0.0, 0.4);
    }
    _scheduleRestoreSpread(keepSpreadIndex);
    _persistLocalSettings();
  }

  void _scheduleRestoreSpread(int spreadIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (spreadCount <= 0) return;
      if (!pageController.hasClients) return;
      final clamped = spreadIndex.clamp(0, spreadCount - 1);
      pageController.jumpToPage(clamped);
    });
    update();
  }

  void setBackgroundColor(Color color) {
    backgroundColorValue.value = color.value;
    _persistLocalSettings();
  }

  void setAutoPlayIntervalSeconds(int seconds) {
    final safe = seconds.clamp(1, 120);
    autoPlayIntervalMs.value = safe * 1000;
    if (isAutoPlaying.value) {
      _startAutoPlay();
    }
    _persistLocalSettings();
  }

  void toggleNavButtons() {
    showNavButtons.toggle();
    _persistLocalSettings();
  }

  void requestOpenSettings() {
    openSettingsNonce.value++;
  }

  double getScale(int index) {
    return scales[index] ?? 1.0;
  }

  void setScale(int index, double scale) {
    scales[index] = scale;
    update();
  }

  void toggleDoubleTapScale(int index, {double baseScale = 1.0}) {
    final double currentScale = scales[index] ?? baseScale;

    double endScale;
    if ((currentScale - baseScale).abs() < 0.0001) {
      endScale = (baseScale * doubleTapScales[1]).clamp(0.5, 10.0);
    } else {
      endScale = baseScale;
    }

    setScale(index, endScale);
  }

  void handleDoubleTapScale(
    int index,
    ExtendedImageGestureState state, {
    double baseScale = 1.0,
  }) {
    final pointerDownPosition = state.pointerDownPosition;
    final double currentScale = scales[index] ?? baseScale;

    double endScale;
    if ((currentScale - baseScale).abs() < 0.0001) {
      endScale = (baseScale * doubleTapScales[1]).clamp(0.5, 10.0);
    } else {
      endScale = baseScale;
    }

    state.handleDoubleTap(
      scale: endScale,
      doubleTapPosition: pointerDownPosition,
    );
    setScale(index, endScale);
  }

  void jumpToPageNumber(int pageNumber1Based) {
    if (pages.isEmpty) return;
    final pageIndex = (pageNumber1Based - 1).clamp(0, pages.length - 1);
    final spreadIdx = spreadIndexForPageIndex(pageIndex);
    pageController.jumpToPage(spreadIdx);
  }

  void _onPageControllerChanged() {
    if (!pageController.hasClients) return;
    final idx = pageController.page?.round() ?? 0;
    handleSpreadChanged(idx);
  }

  void handleSpreadChanged(int spreadIndex) {
    final idx = spreadIndex.clamp(0, spreadCount - 1);
    if (idx == _lastKnownIndex) return;
    _lastKnownIndex = idx;
    currentSpreadIndexRx.value = idx;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      await _saveProgress(spreadIndex: idx);
    });
  }

  Future<void> _saveProgress({required int spreadIndex}) async {
    if (pages.isEmpty) return;
    final spreadIdx = spreadIndex.clamp(0, spreadCount - 1);
    if (spreadIdx == _lastSavedIndex) return;
    _lastSavedIndex = spreadIdx;
    final pageIdx = primaryPageIndexForSpread(spreadIdx);
    await _api.upsertProgress(
      fileHash: fileHash,
      currentPage: pageIdx,
      totalPage: pages.length,
      showLoading: false,
    );
  }

  Color get backgroundColor => Color(backgroundColorValue.value);

  bool get isVertical => readingMode.value == ComicReadingMode.vertical;

  Axis get scrollAxis => isVertical ? Axis.vertical : Axis.horizontal;

  void goLeftAction() {
    if (isVertical) {
      previousPage();
      return;
    }
    if (readingMode.value == ComicReadingMode.rtl) {
      nextPage();
      return;
    }
    previousPage();
  }

  void goRightAction() {
    if (isVertical) {
      nextPage();
      return;
    }
    if (readingMode.value == ComicReadingMode.rtl) {
      previousPage();
      return;
    }
    nextPage();
  }

  void goUpAction() {
    if (isVertical) {
      previousPage();
      return;
    }
    previousPage();
  }

  void goDownAction() {
    if (isVertical) {
      nextPage();
      return;
    }
    nextPage();
  }

  void _loadLocalSettings() {
    try {
      final raw = CacheManager().getString(_settingsKey());
      if (raw == null || raw.trim().isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      final m = map.cast<String, dynamic>();

      final fm = m['fit_mode']?.toString();
      if (fm == 'fit_width') {
        fitMode.value = ComicFitMode.fitWidth;
      } else if (fm == 'fit_screen') {
        fitMode.value = ComicFitMode.fitScreen;
      }

      final pm = m['page_layout']?.toString();
      if (pm == 'double') {
        pageLayout.value = ComicPageLayout.double;
      } else if (pm == 'single') {
        pageLayout.value = ComicPageLayout.single;
      }

      final rm = m['reading_mode']?.toString();
      if (rm == 'rtl') {
        readingMode.value = ComicReadingMode.rtl;
      } else if (rm == 'vertical') {
        readingMode.value = ComicReadingMode.vertical;
      } else if (rm == 'ltr') {
        readingMode.value = ComicReadingMode.ltr;
      }

      final sm = m['side_margin_percent'];
      final smv = sm is num ? sm.toDouble() : double.tryParse('$sm');
      if (smv != null) {
        sideMarginPercent.value = smv.clamp(0.0, 0.4);
      }

      final bg = m['background_color'];
      final bgv = bg is num ? bg.toInt() : int.tryParse('$bg');
      if (bgv != null) {
        backgroundColorValue.value = bgv;
      }

      final ap = m['autoplay_ms'];
      final apv = ap is num ? ap.toInt() : int.tryParse('$ap');
      if (apv != null) {
        autoPlayIntervalMs.value = apv.clamp(1000, 120000);
      }

      final sb = m['show_nav_buttons'];
      if (sb is bool) {
        showNavButtons.value = sb;
      }

      final ac = m['auto_playing'];
      if (ac is bool) {
        isAutoPlaying.value = false;
      }
    } catch (_) {}
  }

  String _settingsKey() {
    final base = ApiController.instance.baseUrl.trim();
    return 'comic_reader_settings_v1#$base';
  }

  Future<void> _persistLocalSettings() async {
    try {
      final out = <String, dynamic>{
        'fit_mode': fitMode.value == ComicFitMode.fitWidth
            ? 'fit_width'
            : 'fit_screen',
        'side_margin_percent': sideMarginPercent.value,
        'page_layout': pageLayout.value == ComicPageLayout.double
            ? 'double'
            : 'single',
        'reading_mode': readingMode.value == ComicReadingMode.rtl
            ? 'rtl'
            : readingMode.value == ComicReadingMode.vertical
            ? 'vertical'
            : 'ltr',
        'background_color': backgroundColorValue.value,
        'autoplay_ms': autoPlayIntervalMs.value,
        'show_nav_buttons': showNavButtons.value,
      };
      await CacheManager().setString(_settingsKey(), jsonEncode(out));
    } catch (_) {}
  }

  Future<void> resetSettings() async {
    fitMode.value = ComicFitMode.fitScreen;
    sideMarginPercent.value = 0;
    pageLayout.value = ComicPageLayout.single;
    readingMode.value = ComicReadingMode.ltr;
    backgroundColorValue.value = Colors.black.value;
    autoPlayIntervalMs.value = 3000;
    showNavButtons.value = true;
    isAutoPlaying.value = false;
    _stopAutoPlay();
    await _persistLocalSettings();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      goLeftAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      goRightAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      goUpAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      goDownAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      goUpAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown ||
        event.logicalKey == LogicalKeyboardKey.space) {
      goDownAction();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      goToFirstPage();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      goToLastPage();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      toggleFitMode();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      cycleSideMargin();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      togglePageLayout();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      toggleFullscreen();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      toggleNavButtons();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      setReadingMode(ComicReadingMode.ltr);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      setReadingMode(ComicReadingMode.rtl);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      setReadingMode(ComicReadingMode.vertical);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyP) {
      toggleAutoPlay();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      toggleControls();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      requestOpenSettings();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (Get.key.currentState?.canPop() ?? false) {
        Get.back();
      }
      return true;
    }
    return false;
  }
}
