import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../models/video_source.dart';
import '../service/video_source_api_service.dart';

class VideoSourceSettingsController extends GetxController {
  final RxList<VideoSource> sources = <VideoSource>[].obs;
  final RxBool loadingSources = false.obs;
  final RxBool scanning = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchSources();
  }

  int getIntervalHours(VideoSource source) {
    final ms = source.scanIntervalMs;
    if (ms <= 0) return 2;
    final hours = (ms / (3600 * 1000)).round();
    return hours.clamp(1, 24);
  }

  bool getIntervalEnabled(VideoSource source) {
    return source.scanInterval == 1 || source.scanIntervalMs > 0;
  }

  Future<void> fetchSources({bool showLoading = false}) async {
    if (loadingSources.value) return;
    loadingSources.value = true;
    try {
      final list = await VideoSourceApiService.instance.listSources(
        showLoading: showLoading,
      );
      sources.assignAll(list);
    } finally {
      loadingSources.value = false;
    }
  }

  Future<bool> addSources(List<String> paths) async {
    return addSourcesWithConfig(paths, mediaType: 'movie', matchNfo: 0);
  }

  Future<bool> addSource(
    String path, {
    required String mediaType,
    required int matchNfo,
  }) async {
    final p = path.trim();
    if (p.isEmpty) return false;
    if (mediaType != 'movie' && mediaType != 'tv') return false;
    if (matchNfo != 0 && matchNfo != 1) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoSourceApiService.instance.addSource(
        p,
        mediaType: mediaType,
        matchNfo: matchNfo,
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      await fetchSources(showLoading: false);
      ToastUtil.show('operation_success'.tr);
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<bool> addSourcesWithConfig(
    List<String> paths, {
    required String mediaType,
    required int matchNfo,
  }) async {
    final uniq = paths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (uniq.isEmpty) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      for (final p in uniq) {
        final res = await VideoSourceApiService.instance.addSource(
          p,
          mediaType: mediaType,
          matchNfo: matchNfo,
          showLoading: false,
        );
        if (!res.success) {
          DialogUtil.dismissLoading();
          ToastUtil.show(res.message ?? 'operation_failed'.tr);
          return false;
        }
      }
      await fetchSources(showLoading: false);
      ToastUtil.show('operation_success'.tr);
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> updateSourceOptimistic(
    VideoSource source, {
    int? scanWhenStart,
    int? scanWhenChange,
    int? scanInterval,
    int? scanIntervalMs,
  }) async {
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final prev = sources[idx];
    final next = prev.copyWith(
      scanWhenStart: scanWhenStart,
      scanWhenChange: scanWhenChange,
      scanInterval: scanInterval,
      scanIntervalMs: scanIntervalMs,
    );
    sources[idx] = next;

    final payload = <String, dynamic>{};
    if (scanWhenStart != null) payload['scan_when_start'] = scanWhenStart;
    if (scanWhenChange != null) payload['scan_when_change'] = scanWhenChange;
    if (scanInterval != null) payload['scan_interval'] = scanInterval;
    if (scanIntervalMs != null) payload['scan_interval_ms'] = scanIntervalMs;

    final res = await VideoSourceApiService.instance.updateSource(
      source.id,
      payload,
      showLoading: false,
    );
    if (!res.success) {
      sources[idx] = prev;
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }

    final data = res.data;
    if (data != null) {
      sources[idx] = VideoSource.fromJson(data);
    }
  }

  Future<void> updateMediaTypeOptimistic(
    VideoSource source,
    String mediaType,
  ) async {
    if (mediaType != 'movie' && mediaType != 'tv') return;
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final prev = sources[idx];
    if (prev.mediaType == mediaType) return;

    final next = prev.copyWith(mediaType: mediaType);
    sources[idx] = next;

    final res = await VideoSourceApiService.instance.updateMediaType(
      source.id,
      mediaType,
      showLoading: false,
    );
    if (!res.success) {
      sources[idx] = prev;
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }

    final data = res.data;
    if (data != null) {
      sources[idx] = VideoSource.fromJson(data);
    }
  }

  Future<void> updateMatchNfoOptimistic(
    VideoSource source,
    int matchNfo,
  ) async {
    if (matchNfo != 0 && matchNfo != 1) return;
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final prev = sources[idx];
    if (prev.matchNfo == matchNfo) return;

    final next = prev.copyWith(matchNfo: matchNfo);
    sources[idx] = next;

    final res = await VideoSourceApiService.instance.updateMatchNfo(
      source.id,
      matchNfo,
      showLoading: false,
    );
    if (!res.success) {
      sources[idx] = prev;
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }

    final data = res.data;
    if (data != null) {
      sources[idx] = VideoSource.fromJson(data);
    }
  }

  Future<void> deleteSourceOptimistic(VideoSource source) async {
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final removed = sources[idx];
    sources.removeAt(idx);

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoSourceApiService.instance.deleteSource(
        source.id,
        showLoading: false,
      );
      if (!res.success) {
        sources.insert(idx, removed);
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
    } catch (_) {
      sources.insert(idx, removed);
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> relocateSource(VideoSource source, String newPath) async {
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoSourceApiService.instance.relocateSource(
        source.id,
        newPath,
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await fetchSources(showLoading: false);
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> scanSource(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    if (scanning.value) return;

    scanning.value = true;
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoSourceApiService.instance.scanSource(
        p,
        showLoading: false,
      );
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_success'.tr);
      await fetchSources(showLoading: false);
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
    } finally {
      scanning.value = false;
      DialogUtil.dismissLoading();
    }
  }

  Future<void> preGenerateThumbnails() async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'photo_source_reset_thumbnails_confirm'.tr,
      confirmText: 'confirm'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await VideoSourceApiService.instance.preGenerateThumbnails(
        showLoading: false,
      );
      DialogUtil.dismissLoading();
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      DialogUtil.dismissLoading();
      ToastUtil.show('operation_failed'.tr);
    }
  }
}
