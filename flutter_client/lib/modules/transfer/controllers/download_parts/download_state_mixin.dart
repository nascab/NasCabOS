part of '../download_controller.dart';

/// 下载状态管理 Mixin
/// 包含所有响应式状态变量和数据结构
mixin DownloadStateMixin on GetxController {
  /// 任务列表
  final tasks = <TransferTask>[].obs;
  final api = FileApiService();

  // Statistics for current selection (used in dialog)
  /// 统计信息（用于下载确认对话框）
  final statsSize = 0.obs;
  final statsCount = 0.obs;
  final isCalculatingStats = false.obs;
  FileStatsService? statsService;

  // Track file sizes for progress calculation: taskId -> totalBytes
  /// 记录文件总大小：taskId -> totalBytes
  final fileSizes = <String, int>{};

  // Track processed bytes per file: taskId -> processedBytes
  /// 记录每个子任务已下载的字节数：taskId -> processedBytes
  /// 用于汇总计算父任务的总进度
  final fileProcessedBytes = <String, int>{};

  // Map download taskId to parent TransferTask
  /// 映射下载任务ID到父任务
  final downloadTaskToParent = <String, TransferTask>{};

  // Throttle updates
  /// 进度更新节流
  DateTime lastUpdate = DateTime.now();
  static const int updateThresholdBytes = 10 * 1024 * 1024; // 10MB
  final bytesSinceLastUpdate = <TransferTask, int>{};

  /// 活动中的 Dio 下载子任务（仅存句柄，用于与进度回调关联）
  final activeDownloadTasks = <String, NascabDownloadWorkerTask>{};

  /// 记录父任务的所有子任务ID：parentTaskId -> `Set<String>`
  final parentToChildrenTasks = <String, Set<String>>{};

  final completedChildTasks = <String, Set<String>>{};

  // Queue for folder downloads: parentTaskId -> Queue<Map<String, dynamic>>
  /// 文件夹下载队列：parentTaskId -> `Queue<Map<String, dynamic>>`
  final folderDownloadQueueLists = <String, Queue<Map<String, dynamic>>>{};

  // Track currently running child task for a parent: parentTaskId -> childTaskId
  /// 记录父任务当前正在运行的子任务ID
  final folderRunningChild = <String, String?>{};
  // Track currently running task info for restore
  /// 记录正在运行的任务信息（用于失败重试或恢复）
  final folderRunningTaskInfo = <String, Map<String, dynamic>>{};

  /// Dio 直连下载的取消令牌（桌面与移动端）
  final desktopCancelTokens = <String, dio.CancelToken>{};

  final webP2pCancels = <String, void Function()>{};
  final webP2pUserCanceled = <String, bool>{};

  /// 用 HTTP 响应头推断出的总长更新子任务 [fileSizes] 与父任务 [totalSize]（列表未给出大小时）。
  void mergeInferredFileTotalForChild(
    String parentId,
    String taskId,
    int inferred,
  ) {
    if (inferred <= 0) return;
    final cur = fileSizes[taskId] ?? 0;
    if (inferred <= cur) return;
    final delta = inferred - cur;
    fileSizes[taskId] = inferred;
    final parent = tasks.firstWhereOrNull((t) => t.id == parentId);
    if (parent == null) return;
    parent.totalSize += delta;
  }
}
