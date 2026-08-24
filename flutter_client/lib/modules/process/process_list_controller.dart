import 'package:get/get.dart';

import 'models/worker_process_item.dart';
import 'service/process_api_service.dart';

class ProcessListController extends GetxController {
  ProcessListController() : _api = ProcessApiService();

  final ProcessApiService _api;

  final RxList<WorkerProcessItem> workers = <WorkerProcessItem>[].obs;
  final RxBool isInitialLoading = true.obs;
  final RxnString loadError = RxnString();

  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    _pollLoop();
  }

  Future<void> _pollLoop() async {
    while (!_closed) {
      await _fetchOnce();
      if (_closed) break;
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _fetchOnce() async {
    final res = await _api.fetchWorkerProcessList();
    if (_closed) return;
    if (!res.success) {
      loadError.value = res.message;
      isInitialLoading.value = false;
      return;
    }
    loadError.value = null;
    workers.assignAll(res.data ?? []);
    isInitialLoading.value = false;
  }

  @override
  void onClose() {
    _closed = true;
    super.onClose();
  }
}
