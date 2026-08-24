import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../base/components/custom_extended_image.dart';
import '../../home/views/pc_home_controller.dart';
import '../../../../core/api/api_controller.dart';
import '../../files/service/file_api_service.dart';
import '../../photo/timeline/service/photo_timeline_api_service.dart';
import '../../photo/timeline/controller/photo_timeline_controller.dart';
import '../../photo/timeline/models/photo_timeline_model.dart';
import '../../folder_view/folder_view_module_type.dart';
import '../../transfer/controllers/download_controller.dart';
import '../../../utils/cache_manager.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';

class CustomGalleryController extends GetxController {
  static CustomGalleryController get instance =>
      Get.find<CustomGalleryController>();

  late ExtendedPageController pageController;
  List<Map<String, dynamic>> get galleryItems => _galleryItems;
  int get initialIndex => galleryInitialIndex.value;

  // 图片浏览器数据
  final RxList<Map<String, dynamic>> _galleryItems =
      <Map<String, dynamic>>[].obs;
  final RxInt galleryInitialIndex = 0.obs;

  // UI状态
  final RxBool isControlsVisible = true.obs;
  final RxBool isAutoPlaying = false.obs;
  final RxBool isLeftArrowVisible = false.obs;
  final RxBool isRightArrowVisible = false.obs;
  final RxBool showInfoButton = true.obs;
  final RxBool isInfoPanelVisible = false.obs;
  final RxBool infoLoading = false.obs;
  final RxString infoErrorText = ''.obs;
  final Rxn<Map<String, dynamic>> infoData = Rxn<Map<String, dynamic>>();
  final RxInt currentIndex = 0.obs;
  int _propertiesFetchSeq = 0;
  String _lastInfoPath = '';

  Future<bool> Function(Map<String, dynamic> item, int index)? deleteHandler;
  Future<void> Function(Map<String, dynamic> item, int index)? downloadHandler;

  /// 当前正在页内播放 Live Photo 的图片索引（null 表示未播放）。
  /// 播放不跳转路由，视频直接覆盖在当前图片上，可继续滑动切换上一张/下一张，切走后自动停止。
  final RxnInt livePlayingIndex = RxnInt();

  bool get isLivePhotoPlaying => livePlayingIndex.value != null;

  /// 在 [index] 对应图片上开始页内播放 Live Photo
  void startLivePlayback(int index) {
    if (index < 0 || index >= _galleryItems.length) return;
    if (livePlayingIndex.value == index) return;
    livePlayingIndex.value = index;
  }

  /// 停止页内 Live Photo 播放
  void stopLivePlayback() {
    livePlayingIndex.value = null;
  }

  // 自动播放计时器
  Timer? _autoPlayTimer;
  static const int autoPlayInterval = 3000; // 3秒切换一次

  Worker? _worker;

  // 双击缩放比例
  final List<double> doubleTapScales = [1.0, 3.0];

  // Track rotation for each image index
  final RxMap<int, int> rotations = <int, int>{}.obs;

  // Track scale state for each image index
  final RxMap<int, double> scales = <int, double>{}.obs;
  final RxMap<int, bool> panoramaCandidates = <int, bool>{}.obs;
  final Set<int> _panoramaDetectionInFlight = <int>{};

  /// 手机端 WiFi 下是否强制使用原图 URL
  bool _wifiOriginalEnabled = false;

  static const double _panoramaMinAspectRatio = 1.8;
  static const double _panoramaMaxAspectRatio = 2.2;

  @override
  void onInit() {
    super.onInit();
    pageController = ExtendedPageController(initialPage: initialIndex);
    currentIndex.value = initialIndex;
    _bindPageController();
    // 首次打开时预加载相邻页（下一张/上一张）
    Future.microtask(() => _preloadAdjacentImages(initialIndex));
    _checkWifiOriginal();

    // 监听galleryInitialIndex变化
    _worker = ever(galleryInitialIndex, (index) {
      if (pageController.hasClients) {
        //界面已经加载的情况下直接跳过去
        pageController.jumpToPage(index);
      } else {
        // 界面没有加载的情况下 卸载然后重新创建控制器
        try {
          pageController.dispose();
        } catch (_) {}
        pageController = ExtendedPageController(initialPage: index);
        currentIndex.value = index;
        _bindPageController();
      }
    });

    // 监听键盘事件
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void onClose() {
    _worker?.dispose();
    pageController.dispose();
    _stopAutoPlay();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.onClose();
  }

  /// 设置图片浏览器的图片列表
  set galleryItems(List<Map<String, dynamic>> items) {
    panoramaCandidates.clear();
    _panoramaDetectionInFlight.clear();
    for (var item in items) {
      final p = item['path']?.toString().trim() ?? '';
      final existingUrl = item['url']?.toString().trim() ?? '';
      final isGif = _isGifItem(item);
      if (p.isNotEmpty &&
          !p.startsWith('http://') &&
          !p.startsWith('https://')) {
        item['url'] = ApiController.instance.getRawFileUrl(p, isRawFile: isGif);
        continue;
      }
      if (existingUrl.isNotEmpty) {
        item['url'] = _normalizeGifUrl(existingUrl, isGif: isGif);
        continue;
      }
      if (p.startsWith('http://') || p.startsWith('https://')) {
        item['url'] = _normalizeGifUrl(p, isGif: isGif);
      }
    }
    if (_wifiOriginalEnabled) {
      for (var item in items) {
        final url = item['url']?.toString() ?? '';
        item['url'] = _appendRawParam(url);
      }
    }
    _galleryItems.value = items;
  }

  bool _isGifItem(Map<String, dynamic> item) {
    return _hasGifExtension(item['name']) ||
        _hasGifExtension(item['path']) ||
        _hasGifExtension(item['url']);
  }

  bool _hasGifExtension(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return false;
    try {
      final uri = Uri.parse(raw);
      final path = uri.path.trim();
      if (path.isNotEmpty) {
        return path.toLowerCase().endsWith('.gif');
      }
    } catch (_) {}
    final clean = raw.split('?').first.trim().toLowerCase();
    return clean.endsWith('.gif');
  }

  String _normalizeGifUrl(String url, {required bool isGif}) {
    final trimmed = url.trim();
    if (!isGif || trimmed.isEmpty) return trimmed;
    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return trimmed;
    }
    if (!uri.path.endsWith('/api/file/rawFile')) {
      return trimmed;
    }
    final params = Map<String, String>.from(uri.queryParameters);
    if (params['raw'] == '1') {
      return trimmed;
    }
    params['raw'] = '1';
    return uri.replace(queryParameters: params).toString();
  }

  void _checkWifiOriginal() {
    if (!DeviceUtils.isMobile) return;
    final enabled =
        CacheManager().getBool(CacheKeys.photoPreviewWifiOriginal) ?? false;
    if (!enabled) return;
    Connectivity().checkConnectivity().then((result) {
      _wifiOriginalEnabled = result.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.other ||
            r == ConnectivityResult.vpn,
      );
      if (_wifiOriginalEnabled && _galleryItems.isNotEmpty) {
        _applyWifiOriginalToAllItems();
      }
    }).catchError((_) {});
  }

  void _applyWifiOriginalToAllItems() {
    for (final item in _galleryItems) {
      final url = item['url']?.toString() ?? '';
      item['url'] = _appendRawParam(url);
    }
    _galleryItems.refresh();
  }

  String _appendRawParam(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    try {
      final uri = Uri.parse(trimmed);
      if (uri.queryParameters['raw'] == '1') return trimmed;
      final params = Map<String, String>.from(uri.queryParameters);
      params['raw'] = '1';
      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return url;
    }
  }

  void configure({
    bool showInfo = true,
    Future<bool> Function(Map<String, dynamic> item, int index)? deleteHandler,
    Future<void> Function(Map<String, dynamic> item, int index)?
    downloadHandler,
  }) {
    showInfoButton.value = showInfo;
    this.deleteHandler = deleteHandler;
    this.downloadHandler = downloadHandler;
    if (!showInfo) isInfoPanelVisible.value = false;
  }

  void rotateLeft(int index) {
    rotations[index] = (rotations[index] ?? 0) - 1;
  }

  void rotateRight(int index) {
    rotations[index] = (rotations[index] ?? 0) + 1;
  }

  void toggleInfoPanel() {
    isInfoPanelVisible.toggle();
    if (isInfoPanelVisible.value) {
      fetchCurrentImageInfo(force: true);
    }
    update();
  }

  void closeGallery() {
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.closeApp('image_view');
      return;
    }
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back();
    }
  }

  int getRotation(int index) {
    return rotations[index] ?? 0;
  }

  /// 获取当前图片的缩放比例
  double getScale(int index) {
    return scales[index] ?? 1.0;
  }

  /// 设置图片的缩放比例
  void setScale(int index, double scale) {
    scales[index] = scale;
    update();
  }

  /// 处理双击缩放逻辑
  void handleDoubleTapScale(int index, ExtendedImageGestureState state) {
    // 获取双击位置（可能为null，需要处理）
    final pointerDownPosition = state.pointerDownPosition;

    // 获取当前缩放比例
    final double currentScale = getScale(index);

    // 确定目标缩放比例
    double endScale;
    if (currentScale == doubleTapScales[0]) {
      endScale = doubleTapScales[1]; // 放大到300%
    } else {
      endScale = doubleTapScales[0]; // 回到原始比例
    }

    // 使用ExtendedImage提供的标准双击缩放方法，确保在点击位置缩放
    state.handleDoubleTap(
      scale: endScale,
      doubleTapPosition: pointerDownPosition,
    );

    // 更新缩放状态
    setScale(index, endScale);
  }

  /// 切换控件显示/隐藏
  void toggleControls() {
    isControlsVisible.toggle();
  }

  void _bindPageController() {
    try {
      pageController.removeListener(_onPageControllerTick);
    } catch (_) {}
    pageController.addListener(_onPageControllerTick);
  }

  void _onPageControllerTick() {
    if (!pageController.hasClients) return;
    final idx = pageController.page?.round() ?? 0;
    if (idx == currentIndex.value) return;
    currentIndex.value = idx;
    // 滑动/切换到其他图片时停止页内 Live Photo 播放
    if (isLivePhotoPlaying && livePlayingIndex.value != idx) {
      stopLivePlayback();
    }
    _preloadAdjacentImages(idx);
    if (isInfoPanelVisible.value) {
      fetchCurrentImageInfo();
    }
  }

  /// 预加载当前页的上一张、下一张，滑动时即显
  void _preloadAdjacentImages(int currentIdx) {
    final items = galleryItems;
    ensurePanoramaCandidate(currentIdx);
    if (currentIdx + 1 < items.length) {
      final url = items[currentIdx + 1]['url']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        CustomExtendedImage.preload(url);
      }
    }
    if (currentIdx - 1 >= 0) {
      final url = items[currentIdx - 1]['url']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        CustomExtendedImage.preload(url);
      }
    }
  }

  Future<void> fetchCurrentImageInfo({bool force = false}) async {
    final item = _currentItem();
    if (item == null) return;
    final rawPath = (item['path'] ?? '').toString();
    final normalized = _normalizeServerPath(rawPath);
    if (normalized.isEmpty || _isUrl(normalized)) {
      infoData.value = null;
      infoErrorText.value = '';
      infoLoading.value = false;
      _lastInfoPath = '';
      return;
    }

    if (!force && _lastInfoPath == normalized && infoData.value != null) return;
    _lastInfoPath = normalized;
    final seq = ++_propertiesFetchSeq;
    infoLoading.value = true;
    infoErrorText.value = '';
    if (force) infoData.value = null;

    try {
      final res = await PhotoTimelineApiService().getPhotoProperties(
        normalized,
      );
      if (seq != _propertiesFetchSeq) return;
      if (!res.success) {
        infoData.value = null;
        infoErrorText.value = res.message ?? 'operation_failed'.tr;
        return;
      }
      final data = Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
      final itemFileHash = (item['file_hash'] ?? item['fileHash'] ?? '')
          .toString()
          .trim();
      final photoIndex = (data['photoIndex'] as Map?)?.cast<String, dynamic>();
      final infoFileHash = (photoIndex?['fileHash'] ?? itemFileHash)
          .toString()
          .trim();
      if (infoFileHash.isNotEmpty &&
          FolderViewModuleType.photo.isServerVersionAtLeast(4)) {
        try {
          final facesRes = await PhotoTimelineApiService().listPhotoFaces(
            fileHash: infoFileHash,
          );
          if (seq != _propertiesFetchSeq) return;
          if (facesRes.success) {
            data['photoFaces'] =
                facesRes.data ?? const <TimelineDetectedFaceItem>[];
          }
        } catch (_) {}
      }
      infoData.value = data;
      infoErrorText.value = '';
    } catch (_) {
      if (seq != _propertiesFetchSeq) return;
      infoData.value = null;
      infoErrorText.value = 'operation_failed'.tr;
    } finally {
      if (seq == _propertiesFetchSeq) {
        infoLoading.value = false;
      }
    }
  }

  int _currentIndex() {
    return pageController.hasClients ? pageController.page?.round() ?? 0 : 0;
  }

  Map<String, dynamic>? _currentItem() {
    final idx = _currentIndex();
    if (idx < 0 || idx >= galleryItems.length) return null;
    return galleryItems[idx];
  }

  int? _photoIdOf(Map<String, dynamic> item) {
    final v = item['photoId'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  bool isPanoramaCandidate(int index) {
    return panoramaCandidates[index] ?? false;
  }

  Future<void> ensurePanoramaCandidate(int index) async {
    if (index < 0 || index >= galleryItems.length) return;
    if (panoramaCandidates.containsKey(index)) return;
    if (_panoramaDetectionInFlight.contains(index)) return;
    _panoramaDetectionInFlight.add(index);
    try {
      final item = galleryItems[index];
      final width = _asDouble(item['width']);
      final height = _asDouble(item['height']);
      var isCandidate = _matchesPanoramaAspectRatio(width, height);
      if (!isCandidate) {
        final size = await _resolveImageSize(item);
        isCandidate = _matchesPanoramaAspectRatio(size?.width, size?.height);
      }
      panoramaCandidates[index] = isCandidate;
    } finally {
      _panoramaDetectionInFlight.remove(index);
    }
  }

  String? getPanoramaImageUrlForItem(Map<String, dynamic> item) {
    final path = (item['path'] ?? '').toString().trim();
    if (path.isNotEmpty && !_isUrl(path)) {
      return ApiController.instance.getRawFileUrl(
        path,
        withAccessToken: true,
        isRawFile: true,
      );
    }
    final url = (item['url'] ?? '').toString().trim();
    if (url.isNotEmpty) return url;
    if (_isUrl(path)) return path;
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  bool _matchesPanoramaAspectRatio(double? width, double? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return false;
    }
    if (width <= height) return false;
    final ratio = width / height;
    return ratio >= _panoramaMinAspectRatio && ratio <= _panoramaMaxAspectRatio;
  }

  Future<Size?> _resolveImageSize(Map<String, dynamic> item) async {
    final url = getPanoramaImageUrlForItem(item);
    if (url == null || url.isEmpty) return null;
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    final completer = Completer<Size?>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
      },
      onError: (exception, stackTrace) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    stream.addListener(listener);
    try {
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
    } finally {
      stream.removeListener(listener);
    }
  }

  bool _isUrl(String v) {
    final uri = Uri.tryParse(v);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _normalizeServerPath(String v) {
    var x = v.trim();
    if (x.isEmpty) return x;
    x = x.replaceAll('\\', '/');
    x = x.replaceAll(RegExp('/+'), '/');
    while (x.length > 1 && x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  String _serverDirname(String v) {
    final x = _normalizeServerPath(v);
    final i = x.lastIndexOf('/');
    if (i <= 0) return '';
    return x.substring(0, i);
  }

  String _serverJoin(String dir, String name) {
    final d = _normalizeServerPath(dir);
    final n = name.trim().replaceAll('\\', '/');
    if (d.isEmpty) return _normalizeServerPath(n);
    if (n.isEmpty) return d;
    return _normalizeServerPath('$d/$n');
  }

  void _removeItemAndFixPage({required int removedIndex}) {
    if (removedIndex < 0 || removedIndex >= _galleryItems.length) return;
    _galleryItems.removeAt(removedIndex);
    if (_galleryItems.isEmpty) {
      closeGallery();
      return;
    }
    final safeIndex = removedIndex >= _galleryItems.length
        ? _galleryItems.length - 1
        : removedIndex;
    if (pageController.hasClients) {
      pageController.jumpToPage(safeIndex);
    } else {
      galleryInitialIndex.value = safeIndex;
    }
  }

  /// 删除当前图片
  Future<void> deleteCurrentImage() async {
    final item = _currentItem();
    if (item == null) return;

    final currentIndex = _currentIndex();
    final handler = deleteHandler;
    if (handler != null) {
      final ok = await handler(item, currentIndex);
      if (ok) _removeItemAndFixPage(removedIndex: currentIndex);
      return;
    }
    final photoId = _photoIdOf(item);
    final isPhoto = photoId != null && photoId > 0;

    if (isPhoto) {
      try {
        final res = await PhotoTimelineApiService().batchTrash([photoId]);
        if (!res.success) {
          ToastUtil.show(
            (res.code == 403 ? 'permission_denied' : 'operation_failed').tr,
          );
          return;
        }
        final timelineTag = (item['photoTimelineTag'] ?? '').toString().trim();
        if (timelineTag.isNotEmpty &&
            Get.isRegistered<PhotoTimelineController>(tag: timelineTag)) {
          Get.find<PhotoTimelineController>(
            tag: timelineTag,
          ).removeTrashedFromMemory([photoId]);
        }
        _removeItemAndFixPage(removedIndex: currentIndex);
        ToastUtil.show('photo_trashed_success'.tr);
      } catch (_) {
        ToastUtil.show('operation_failed'.tr);
      }
      return;
    }

    final rawPath = item['path']?.toString() ?? '';
    final path = _normalizeServerPath(rawPath);
    if (path.isEmpty || _isUrl(path)) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }

    final isShellSupported = ApiController.instance.state.shellSupported;
    if (isShellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(
        title: 'need_confirm'.tr,
        content: 'folder_delete_confirm'.trParams({'fileCount': '1'}),
        cancelText: 'cancel'.tr,
        option1Text: 'delete'.tr,
        option2Text: 'put_in_recycle_bin'.tr,
        option2IsPrimary: true,
        onOption1: () async {
          final res = await FileApiService().deleteEntries([
            path,
          ], recycle: false);
          if (!res.success) {
            DialogUtil.showErrorDialog(
              message: res.message ?? 'operation_failed'.tr,
            );
            return;
          }
          _removeItemAndFixPage(removedIndex: currentIndex);
          ToastUtil.show('delete_success'.tr);
        },
        onOption2: () async {
          final res = await FileApiService().deleteEntries([
            path,
          ], recycle: true);
          if (!res.success) {
            DialogUtil.showErrorDialog(
              message: res.message ?? 'operation_failed'.tr,
            );
            return;
          }
          _removeItemAndFixPage(removedIndex: currentIndex);
          ToastUtil.show('delete_success'.tr);
        },
      );
    } else {
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'folder_delete_confirm'.trParams({'fileCount': '1'}),
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed != true) return;
      final res = await FileApiService().deleteEntries([path], recycle: false);
      if (!res.success) {
        DialogUtil.showErrorDialog(
          message: res.message ?? 'operation_failed'.tr,
        );
        return;
      }
      _removeItemAndFixPage(removedIndex: currentIndex);
      ToastUtil.show('delete_success'.tr);
    }
  }

  /// 下载当前图片
  Future<void> downloadCurrentImage() async {
    final item = _currentItem();
    if (item == null) return;

    final currentIndex = _currentIndex();
    final handler = downloadHandler;
    if (handler != null) {
      await handler(item, currentIndex);
      return;
    }

    final path = (item['path'] ?? '').toString().trim();
    final url = (item['url'] ?? '').toString().trim();
    final primary = path.isNotEmpty ? path : url;
    if (primary.isEmpty) return;

    final photoId = _photoIdOf(item);
    final liveFilename = (item['liveFilename'] ?? '').toString().trim();
    final rawFilename = (item['rawFilename'] ?? '').toString().trim();

    final wanted = <String>{};
    wanted.add(primary);

    if (photoId != null && photoId > 0 && path.isNotEmpty && !_isUrl(path)) {
      final dir = _serverDirname(path);
      if (liveFilename.isNotEmpty) {
        wanted.add(_serverJoin(dir, liveFilename));
      }
      if (rawFilename.isNotEmpty) {
        wanted.add(_serverJoin(dir, rawFilename));
      }
    }

    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(wanted.toList());
  }

  /// 切换自动播放
  void toggleAutoPlay() {
    isAutoPlaying.toggle();
    if (isAutoPlaying.value) {
      _startAutoPlay();
    } else {
      _stopAutoPlay();
    }
  }

  /// 开始自动播放
  void _startAutoPlay() {
    _stopAutoPlay();
    _autoPlayTimer = Timer.periodic(
      Duration(milliseconds: autoPlayInterval),
      (_) => nextImage(),
    );
  }

  /// 停止自动播放
  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  /// 上一张图片
  void previousImage() {
    final currentIndex = pageController.hasClients
        ? pageController.page?.round() ?? 0
        : 0;
    if (currentIndex > 0) {
      pageController.jumpToPage(currentIndex - 1);
    }
  }

  /// 下一张图片
  void nextImage() {
    final currentIndex = pageController.hasClients
        ? pageController.page?.round() ?? 0
        : 0;
    if (currentIndex < galleryItems.length - 1) {
      pageController.jumpToPage(currentIndex + 1);
    }
  }

  /// 显示左箭头
  void showLeftArrow() {
    isLeftArrowVisible.value = true;
  }

  /// 隐藏左箭头
  void hideLeftArrow() {
    isLeftArrowVisible.value = false;
  }

  /// 显示右箭头
  void showRightArrow() {
    isRightArrowVisible.value = true;
  }

  /// 隐藏右箭头
  void hideRightArrow() {
    isRightArrowVisible.value = false;
  }

  /// 若当前项为 Live Photo 且存在视频文件，返回其播放 URL（Web 端优先尝试源文件直链）；否则返回 null。
  /// 支持两种 Live Photo：
  ///  - 分离式（普通）：isLvp=1, liveFilename 指向同目录下的独立视频文件
  ///  - 合并式（OPPO）：isMergeLvp=1, 视频嵌入 JPEG 文件内部，通过服务端提取接口播放
  String? getLiveVideoUrlForItem(Map<String, dynamic> item) {
    final isLvp = (item['isLvp'] is int)
        ? (item['isLvp'] as int)
        : (int.tryParse(item['isLvp']?.toString() ?? '') ?? 0);
    if (isLvp != 1) return null;

    final isMergeLvp = (item['isMergeLvp'] is int)
        ? (item['isMergeLvp'] as int)
        : (int.tryParse(item['isMergeLvp']?.toString() ?? '') ?? 0);

    // 合并式 LVP（OPPO）：照片文件本身包含视频，使用提取接口
    if (isMergeLvp == 1) {
      final photoPath = (item['path'] ?? '').toString().trim();
      if (photoPath.isEmpty) return null;
      return ApiController.instance.getMergeLvpVideoUrl(photoPath);
    }

    // 分离式 LVP：查找同目录下的独立视频文件
    final liveFilename = (item['liveFilename'] ?? '').toString().trim();
    if (liveFilename.isEmpty) return null;
    final photoPath = (item['path'] ?? '').toString().trim();
    if (photoPath.isEmpty) return null;
    final dir = _serverDirname(photoPath);
    final livePath = _serverJoin(dir, liveFilename);
    if (livePath.isEmpty) return null;
    return ApiController.instance.getRawFileUrl(
      livePath,
      withAccessToken: true,
      isRawFile: true,
    );
  }

  /// Web 端当源格式非 mp4/m4v 时返回转码 MP4 流 URL，用于源文件播放失败时的兜底；非 Web 或已是 mp4 时返回 null。
  /// 合并式 LVP（OPPO）提取后已是 MP4，不需要兜底。
  String? getLiveVideoFallbackUrlForItem(Map<String, dynamic> item) {
    if (!kIsWeb) return null;

    final isMergeLvp = (item['isMergeLvp'] is int)
        ? (item['isMergeLvp'] as int)
        : (int.tryParse(item['isMergeLvp']?.toString() ?? '') ?? 0);
    // 合并式 LVP：服务端提取后已是 MP4，无需转码兜底
    if (isMergeLvp == 1) return null;

    final liveFilename = (item['liveFilename'] ?? '').toString().trim();
    if (liveFilename.isEmpty) return null;
    final ext = liveFilename.toLowerCase().split('.').last;
    if (ext == 'mp4' || ext == 'm4v') return null;
    final photoPath = (item['path'] ?? '').toString().trim();
    if (photoPath.isEmpty) return null;
    final dir = _serverDirname(photoPath);
    final livePath = _serverJoin(dir, liveFilename);
    if (livePath.isEmpty) return null;
    return ApiController.instance.getVideoStreamMp4Url(livePath);
  }

  /// 处理键盘事件
  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        previousImage();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nextImage();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        unawaited(deleteCurrentImage());
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (isLivePhotoPlaying) {
          stopLivePlayback();
          return true;
        }
        closeGallery();
        return true;
      } else if ((event.logicalKey == LogicalKeyboardKey.keyI) &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        toggleInfoPanel();
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        if (isLivePhotoPlaying) {
          stopLivePlayback();
          return true;
        }
        final item = _currentItem();
        if (item != null) {
          final url = getLiveVideoUrlForItem(item);
          if (url != null) {
            startLivePlayback(_currentIndex());
            return true;
          }
        }
      }
    }
    return false;
  }
}
