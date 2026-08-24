import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../models/music_source.dart';
import '../service/music_source_api_service.dart';

class MusicSourceSettingsController extends GetxController {
  final RxList<MusicSource> sources = <MusicSource>[].obs;
  final RxBool loadingSources = false.obs;
  final RxBool scanning = false.obs;

  @override
  void onInit() {
    super.onInit();
    fetchSources();
  }

  int getIntervalHours(MusicSource source) {
    final ms = source.scanIntervalMs;
    if (ms <= 0) return 2;
    final hours = (ms / (3600 * 1000)).round();
    return hours.clamp(1, 24);
  }

  bool getIntervalEnabled(MusicSource source) {
    return source.scanInterval == 1 || source.scanIntervalMs > 0;
  }

  Future<void> fetchSources({bool showLoading = false}) async {
    if (loadingSources.value) return;
    loadingSources.value = true;
    try {
      final list = await MusicSourceApiService.instance.listSources(
        showLoading: showLoading,
      );
      sources.assignAll(list);
    } finally {
      loadingSources.value = false;
    }
  }

  Future<bool> addSources(List<String> paths) async {
    final uniq = paths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (uniq.isEmpty) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      for (final p in uniq) {
        final res = await MusicSourceApiService.instance.addSource(
          p,
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
    MusicSource source, {
    int? scanWhenStart,
    int? scanWhenChange,
    int? scanInterval,
    int? scanIntervalMs,
    String? showType,
  }) async {
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final prev = sources[idx];
    final next = prev.copyWith(
      scanWhenStart: scanWhenStart,
      scanWhenChange: scanWhenChange,
      scanInterval: scanInterval,
      scanIntervalMs: scanIntervalMs,
      showType: showType,
    );
    sources[idx] = next;

    final payload = <String, dynamic>{};
    if (scanWhenStart != null) payload['scan_when_start'] = scanWhenStart;
    if (scanWhenChange != null) payload['scan_when_change'] = scanWhenChange;
    if (scanInterval != null) payload['scan_interval'] = scanInterval;
    if (scanIntervalMs != null) payload['scan_interval_ms'] = scanIntervalMs;
    if (showType != null) payload['show_type'] = showType;

    final res = await MusicSourceApiService.instance.updateSource(
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
      sources[idx] = MusicSource.fromJson(data);
    }
  }

  Future<void> relocateSource(MusicSource source, String newPath) async {
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await MusicSourceApiService.instance.relocateSource(
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

  Future<void> deleteSourceOptimistic(MusicSource source) async {
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx < 0) return;

    final removed = sources[idx];
    sources.removeAt(idx);

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await MusicSourceApiService.instance.deleteSource(
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

  Future<void> scanSource(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    if (scanning.value) return;

    scanning.value = true;
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await MusicSourceApiService.instance.scanSource(
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
}
