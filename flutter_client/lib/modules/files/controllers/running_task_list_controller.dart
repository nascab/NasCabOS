import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../transfer/models/file_operation_log.dart';
import '../../transfer/repositories/file_log_repository.dart';
import '../../../utils/toast_util.dart';

/// Controller for the running task list dialog (copy/move progress).
/// Fetches only PROCESSING and WAIT logs, refreshes every 1s after previous request completes.
class RunningTaskListController extends GetxController {
  final FileLogRepository _repository = FileLogRepository();

  final RxList<FileOperationLog> logs = <FileOperationLog>[].obs;
  VoidCallback? _closeCallback;
  bool _fetching = false;
  bool _hadNonEmptyOnce = false;
  Timer? _timer;
  static const Duration _pollInterval = Duration(seconds: 1);

  void setCloseCallback(VoidCallback? cb) {
    _closeCallback = cb;
  }

  @override
  void onReady() {
    super.onReady();
    _fetch();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _timer = null;
    super.onClose();
  }

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final response = await _repository.getFileLogs(
        stateList: ['PROCESSING', 'WAIT'],
        page: 1,
        pageSize: 100,
      );
      if (!response.success || response.data == null) {
        _scheduleNext();
        return;
      }
      final list = response.data!.list;
      if (list.isNotEmpty) _hadNonEmptyOnce = true;
      logs.assignAll(list);
      if (list.isEmpty && _hadNonEmptyOnce) {
        _timer?.cancel();
        _timer = null;
        _closeCallback?.call();
        return;
      }
      _scheduleNext();
    } catch (_) {
      _scheduleNext();
    } finally {
      _fetching = false;
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_pollInterval, () {
      _fetch();
    });
  }

  Future<void> cancelTask(FileOperationLog task) async {
    final response = await _repository.cancelFileOperation(task.id);
    if (response.success) {
      await _fetch();
    } else {
      ToastUtil.show(response.message ?? 'operation_failed'.tr);
    }
  }

  void closeDialog() {
    _timer?.cancel();
    _timer = null;
    _closeCallback?.call();
  }
}
