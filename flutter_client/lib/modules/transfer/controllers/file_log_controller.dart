import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/file_operation_log.dart';
import '../repositories/file_log_repository.dart';
import '../../../utils/toast_util.dart';

class FileLogController extends GetxController {
  final FileLogRepository _repository = FileLogRepository();

  // State
  final RxList<FileOperationLog> logs = <FileOperationLog>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadMore = false.obs;
  final RxInt total = 0.obs;

  // Pagination
  int currentPage = 1;
  final int pageSize = 20;
  final ScrollController scrollController = ScrollController();

  // Filters
  final RxString selectedStatus = 'processing'.obs;
  final RxString selectedType = 'all'.obs;
  final RxString searchKeyword = ''.obs;

  final Map<String, String> statusOptions = {
    'processing': 'processing',
    'waiting': 'waiting',
    'completed': 'completed',
    'failed': 'failed',
  };

  final Map<String, String> typeOptions = {
    'all': 'all',
    'copy': 'copy',
    'move': 'move',
    'delete': 'delete',
    'rename': 'rename',
  };

  // Auto Refresh
  Timer? _refreshTimer;
  final int refreshInterval = 3; // seconds

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);

    // Debounce search
    debounce(
      searchKeyword,
      (_) => _loadData(refresh: true),
      time: const Duration(milliseconds: 500),
    );

    _loadData(refresh: true);
    _startAutoRefresh();
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    _stopAutoRefresh();
    super.onClose();
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      if (!isLoadMore.value && !isLoading.value && logs.length < total.value) {
        onLoadMore();
      }
    }
  }

  void onStatusChanged(String? status) {
    if (status != null && status != selectedStatus.value) {
      selectedStatus.value = status;
      _loadData(refresh: true);

      if (status == 'processing') {
        _startAutoRefresh();
      } else {
        _stopAutoRefresh();
      }
    }
  }

  void onTypeChanged(String? type) {
    if (type != null && type != selectedType.value) {
      selectedType.value = type;
      _loadData(refresh: true);
    }
  }

  List<String> _getCurrentStateList() {
    switch (selectedStatus.value) {
      case 'processing':
        return ['PROCESSING'];
      case 'waiting':
        return ['WAIT'];
      case 'completed':
        return ['SUCCESS'];
      case 'failed':
        return ['ERROR', 'CANCELLED', 'INTERRUPTED'];
      default:
        return [];
    }
  }

  List<String>? _getCurrentTypes() {
    if (selectedType.value == 'all') return null;
    return [selectedType.value];
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) {
      currentPage = 1;
      isLoading.value = true;
    } else {
      currentPage++;
      isLoadMore.value = true;
    }

    try {
      final response = await _repository.getFileLogs(
        types: _getCurrentTypes(),
        stateList: _getCurrentStateList(),
        page: currentPage,
        pageSize: pageSize,
        keyword: searchKeyword.value,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        total.value = data.total;

        if (refresh) {
          logs.assignAll(data.list);
        } else {
          logs.addAll(data.list);
        }
      } else {
        // Handle error
      }
    } catch (e) {
      // Handle error
    } finally {
      if (refresh) {
        isLoading.value = false;
      } else {
        isLoadMore.value = false;
      }
    }
  }

  // Exposed methods for UI
  Future<void> onRefresh() async => await _loadData(refresh: true);
  void onLoadMore() => _loadData(refresh: false);

  void onSearch(String value) {
    searchKeyword.value = value;
  }

  Future<void> clearLogs({String? type}) async {
    List<String>? stateList;
    if (type == 'completed') {
      stateList = ['SUCCESS'];
    } else if (type == 'error') {
      stateList = ['ERROR', 'CANCELLED', 'INTERRUPTED'];
    } else if (type == 'waiting') {
      stateList = ['WAIT'];
    }
    // type == 'all' or null -> stateList = null (clear all)

    final response = await _repository.clearLogs(stateList: stateList);
    if (response.success) {
      ToastUtil.show('file_logs_cleared'.tr, title: 'operation_success'.tr);
      onRefresh();
    } else {
      ToastUtil.show(response.message ?? '', title: 'operation_failed'.tr);
    }
  }

  // Auto Refresh Logic
  void _startAutoRefresh() {
    _stopAutoRefresh();
    if (selectedStatus.value == 'processing') {
      _refreshTimer = Timer.periodic(Duration(seconds: refreshInterval), (
        timer,
      ) {
        _loadData(refresh: true);
      });
    }
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> cancelTask(FileOperationLog task) async {
    final response = await _repository.cancelFileOperation(task.id);
    if (response.success) {
      // Refresh list
      onRefresh();
    } else {
      ToastUtil.show(response.message ?? 'Cancel failed', title: 'Error'.tr);
    }
  }
}
