import 'dart:async';
import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../service/img_batch_compress_api_service.dart';

class ImgBatchCompressController extends GetxController {
  final _api = ImgBatchCompressApiService();

  final RxList<Map<String, dynamic>> tasks = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final opLoadingById = <int, bool>{}.obs;

  Timer? _pollTimer;
  Completer<void>? _refreshCompleter;

  @override
  void onInit() {
    super.onInit();
    refreshList(showLoading: false, clearOnFail: true, waitIfBusy: false);
    _startPolling();
  }

  @override
  void onClose() {
    _stopPolling();
    super.onClose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshList(showLoading: false, clearOnFail: false, waitIfBusy: false);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refreshList({
    bool showLoading = true,
    bool clearOnFail = true,
    bool waitIfBusy = true,
  }) async {
    final inflight = _refreshCompleter;
    if (inflight != null && !inflight.isCompleted) {
      if (!waitIfBusy) return;
      await inflight.future;
    }
    _refreshCompleter = Completer<void>();
    isLoading.value = true;
    errorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list(page: 1);
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        if (clearOnFail) tasks.assignAll(const []);
        return;
      }

      final items = (res.data ?? const <String, dynamic>{})['items'];
      final list = (items is List ? items : const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      tasks.assignAll(list);
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      if (clearOnFail) tasks.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
      _refreshCompleter?.complete();
    }
  }

  Future<bool> upsert({
    int? id,
    required String sourcePath,
    required String targetPath,
    required String outFormat,
    required int quality,
    int? outSize,
    required String nonImagePolicy,
  }) async {
    final s = sourcePath.trim();
    final t = targetPath.trim();
    if (s.isEmpty || t.isEmpty) {
      ToastUtil.show('media_tool_img_batch_required'.tr);
      return false;
    }

    final fmt = outFormat.trim().toLowerCase();
    if (fmt != 'jpeg' && fmt != 'png' && fmt != 'webp') {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    final q = quality.clamp(30, 100);
    final pol = nonImagePolicy.trim().toLowerCase();
    if (pol != 'skip' && pol != 'copy') {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    final os = outSize?.clamp(10, 20000);
    final res = await _api.upsert(
      id: id,
      sourcePath: s,
      targetPath: t,
      outFormat: fmt,
      quality: q,
      outSize: os,
      nonImagePolicy: pol,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
    return true;
  }

  Future<bool> remove({required int id}) async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'file_share_server_delete_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return false;

    final res = await _api.delete(id: id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  Future<void> start({required int id}) async {
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.start(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      await refreshList(
        showLoading: false,
        clearOnFail: false,
        waitIfBusy: true,
      );
      return;
    }
    await refreshList(showLoading: false, clearOnFail: false, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> stop({required int id}) async {
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.stop(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      await refreshList(
        showLoading: false,
        clearOnFail: false,
        waitIfBusy: true,
      );
      return;
    }
    await refreshList(showLoading: false, clearOnFail: false, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
  }
}
