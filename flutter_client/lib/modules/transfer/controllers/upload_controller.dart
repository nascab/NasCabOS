import 'dart:async';
import 'dart:io';
import 'package:NasCabOS/modules/home/views/pc_home_controller.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart' hide MultipartFile, FormData, Response;
import 'package:permission_handler/permission_handler.dart';
import '../../../core/routes/app_routes.dart';
import 'task_center_controller.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path/path.dart' as p;

import '../models/transfer_task.dart';
import 'upload_parts/upload_transfer_helper.dart';
import 'upload_parts/upload_transfer_uploader.dart';
import 'upload_parts/upload_web_file_helper.dart';
import '../../../core/notification/transfer_work_notification_hub.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/cache_manager.dart';
import '../../../core/api/dio_bad_certificate_compat.dart';
import '../utils/upload_temp_file_cleaner.dart';

/// 传输控制器类
/// 负责管理文件传输任务的核心控制器
class UploadController extends GetxController {
  /// 获取传输控制器单例
  /// 使用 GetX 的依赖注入系统获取实例
  static UploadController get instance => Get.find<UploadController>();

  /// 传输任务列表（响应式）
  /// 包含所有上传和下载任务
  final RxList<TransferTask> tasks = <TransferTask>[].obs;

  /// 最大并发上传数（响应式）
  /// 控制同时进行的上传任务数量
  final RxInt maxConcurrent = 1.obs;

  /// 命名策略（响应式）
  /// 用于处理同名文件冲突，可选值：
  /// - 'skip': 跳过已存在的文件
  /// - 'overwrite': 覆盖已存在的文件
  /// - 'rename': 重命名新文件
  final RxString nameStrategy = 'skip'.obs;

  static const String saveTypeCacheKey = 'app_upload_center_save_type';

  final RxString saveType = ''.obs;

  /// 上次UI刷新时间
  /// 用于节流刷新，避免频繁更新UI
  DateTime _lastUiRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// 节流刷新函数
  /// 每隔200毫秒刷新一次UI，避免频繁更新导致的性能问题
  bool _refreshThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastUiRefresh).inMilliseconds >= 200) {
      tasks.refresh();
      _lastUiRefresh = now;
      return true;
    }
    return false;
  }

  /// 当前正在处理的任务ID列表
  final List<String> _processingIds = [];

  bool _queueProcessing = false;

  /// 存储文件引用映射
  /// - key: 任务ID
  /// - value: 文件对象
  ///   - Web平台: 浏览器原生File对象
  ///   - 桌面平台: XFile对象（包装了文件路径）
  final Map<String, dynamic> _activeFiles = {};

  /// Dio实例，用于发送HTTP请求
  /// 与主API使用的Dio实例分离，以便单独配置超时和进度处理
  late dio.Dio _dio;

  /// 存储取消令牌映射
  /// - key: 任务ID
  /// - value: 取消令牌，用于取消上传任务
  final Map<String, dio.CancelToken> _cancelTokens = {};

  /// 文件上传器（全平台 Dio + UploadCore）
  late final UploadTransferUploader _uploader;

  /// 控制器初始化方法
  /// 在控制器创建时调用，初始化各种资源
  @override
  void onInit() {
    super.onInit();
    _initDio(); // 初始化Dio实例
    _loadCachedUploadOptions();
    // _loadTasks(); // 加载保存的任务

    _uploader = UploadTransferUploader(
      _activeFiles,
      _processingIds,
      _cancelTokens,
      _dio,
      tasks,
      nameStrategy,
      saveType,
      _refreshThrottled,
    );

    // 监听任务列表变化，自动保存
    // ever(tasks, (_) => _saveTasks());

    // 监听最大并发数变化，重新处理队列
    // 定期监控队列或在任务完成时重新处理
    ever(maxConcurrent, (_) => _processQueue());

    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureNotificationPermission());
      });
    }
  }

  void _loadCachedUploadOptions() {
    try {
      final v = CacheManager().getString(saveTypeCacheKey)?.trim() ?? '';
      if (v.isEmpty || v == 'year' || v == 'month' || v == 'day') {
        saveType.value = v;
      }
    } catch (_) {}
  }

  Future<void> setSaveType(String type) async {
    final v = type.trim().toLowerCase();
    if (v.isNotEmpty && v != 'year' && v != 'month' && v != 'day') return;
    saveType.value = v;
    await CacheManager().setString(saveTypeCacheKey, v);
  }

  Future<void> _ensureNotificationPermission() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    final status = await Permission.notification.status;
    if (status.isGranted) return;

    if (status.isPermanentlyDenied) {
      DialogUtil.showConfirmDialog(
        title: 'permission_transfer_notification_title'.tr,
        content: 'permission_transfer_notification_content'.tr,
        confirmText: 'open_settings'.tr,
        cancelText: 'cancel'.tr,
        onConfirm: () => openAppSettings(),
      );
      return;
    }

    final result = await Permission.notification.request();
    if (result.isGranted) return;
    DialogUtil.showConfirmDialog(
      title: 'permission_transfer_notification_title'.tr,
      content: 'permission_transfer_notification_content'.tr,
      confirmText: 'open_settings'.tr,
      cancelText: 'cancel'.tr,
      onConfirm: () => openAppSettings(),
    );
  }

  void triggerQueueProcessing() {
    _processQueue();
  }

  void addTaskToList(dynamic taskItem) {
    final List<TransferTask> list = taskItem is List<TransferTask>
        ? taskItem
        : <TransferTask>[taskItem as TransferTask];
    tasks.addAll(list);
    for (final t in list) {
      if (t.status == TransferStatus.pending) {
        _cancelTokens.putIfAbsent(t.id, () => dio.CancelToken());
      }
    }
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      try {
        final home = PcHomeController.instance;
        final taskCenter = Get.isRegistered<TaskCenterController>()
            ? TaskCenterController.to
            : Get.put(TaskCenterController());
        taskCenter.jumpToPage(0);
        home.openApp(
          windowId: 'task_center',
          viewBuilder: home.builtinAppViewBuilder('task_center'),
          title: 'app_task_center'.tr,
          icon: home.buildAppIcon('task_center'),
        );
      } catch (e) {
        debugPrint('[UploadController] open task center failed: $e');
      }
    } else if (DeviceUtils.isMobile) {
      if (Get.currentRoute != AppRoutes.appUploadCenter) {
        Get.toNamed(AppRoutes.appUploadCenter);
      }
    }
  }

  Future<List<TransferTask>> enqueueXFiles(
    List<dynamic> files,
    String targetDir, {
    bool startImmediately = true,
  }) async {
    final target = targetDir.trim();
    if (target.isEmpty) return const <TransferTask>[];

    final newTasks = <TransferTask>[];
    for (final item in files) {
      XFile? file;
      String? nameOverride;
      if (item is XFile) {
        file = item;
      } else if (item is Map) {
        final f = item['file'];
        if (f is XFile) file = f;
        final n = item['name'];
        if (n is String && n.trim().isNotEmpty) nameOverride = n.trim();
      }
      if (file == null) continue;

      final name = nameOverride ?? file.name;
      final size = await file.length();

      if (UploadTransferHelper.isFileAlreadyInUpload(tasks, name, target)) {
        continue;
      }
      if (size == 0) continue;

      final taskId = "${DateTime.now().microsecondsSinceEpoch}_$name";
      final task = TransferTask(
        id: taskId,
        name: name,
        localPath: file.path,
        remotePath: target,
        type: TransferType.upload,
        totalSize: size,
        status: startImmediately
            ? TransferStatus.pending
            : TransferStatus.paused,
        chunkSize: UploadTransferHelper.calculateChunkSize(size),
      );
      _activeFiles[taskId] = file;
      newTasks.add(task);
    }

    if (newTasks.isEmpty) return const <TransferTask>[];
    addTaskToList(newTasks);
    if (startImmediately) {
      _processQueue();
    } else {
      tasks.refresh();
    }
    return newTasks;
  }

  Future<void> _addPickedPlatformFilesToUpload(
    List<PlatformFile> picked,
    String targetDir,
  ) async {
    final newTasks = <TransferTask>[];
    int skippedDup = 0;
    int skippedEmpty = 0;

    for (final pickedFile in picked) {
      final path = (pickedFile.path ?? '').trim();
      if (path.isEmpty) continue;

      final name = pickedFile.name.trim().isNotEmpty
          ? pickedFile.name.trim()
          : p.basename(path);
      final size = pickedFile.size;

      if (UploadTransferHelper.isFileAlreadyInUpload(tasks, name, targetDir)) {
        ToastUtil.show("file_allready_in_upload_queue".tr);
        skippedDup++;
        continue;
      }
      if (size <= 0) {
        skippedEmpty++;
        continue;
      }

      final taskId =
          "${DateTime.now().millisecondsSinceEpoch.toString()}_$name";
      final file = XFile(path, name: name);
      _activeFiles[taskId] = file;

      newTasks.add(
        TransferTask(
          id: taskId,
          name: name,
          localPath: path,
          remotePath: targetDir,
          type: TransferType.upload,
          totalSize: size,
          status: TransferStatus.pending,
          chunkSize: UploadTransferHelper.calculateChunkSize(size),
        ),
      );
    }

    if (newTasks.isNotEmpty) {
      addTaskToList(newTasks);
      ToastUtil.show("file_task_upload_added".tr);
      _processQueue();
      return;
    }

    debugPrint(
      '[UploadController] _addPickedPlatformFilesToUpload: picked=${picked.length} skippedDup=$skippedDup skippedEmpty=$skippedEmpty',
    );
  }

  /// 初始化Dio实例
  /// 配置超时时间和其他选项
  void _initDio() {
    _dio = createDioWithBadCertificateCompat(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 30), // 连接超时时间：30秒
        // 上传可能需要很长时间，设置合理的接收超时或在分块中处理
        receiveTimeout: const Duration(seconds: 30), // 接收超时时间：30秒
      ),
    );
  }

  // --- Actions ---
  /// [ensureSupported] 可选；在 Web 上若传入，会在用户选完文件后再校验（避免 Safari 因异步失去用户手势导致无法打开选择器）。
  Future<void> pickAndUpload(
    String targetDir, {
    Future<bool> Function()? ensureSupported,
  }) async {
    try {
      if (kIsWeb) {
        // Web: 必须先在同一次用户手势中触发选择器，Safari 否则会拦截
        final files = await UploadWebFileHelper.pickFiles();
        // Safari: 选文件后的延续有时不执行，放到下一帧跑确保稳定触发上传
        final done = Completer<void>();
        void run() async {
          try {
            if (ensureSupported != null) {
              final supported = await ensureSupported();
              if (!supported) {
                done.complete();
                return;
              }
            }
            await _addFilesToUpload(files, targetDir);
          } catch (e) {
            ToastUtil.show('Failed to pick files: $e', title: 'Error'.tr);
          } finally {
            if (!done.isCompleted) done.complete();
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => run());
        await done.future;
        return;
      }

      // Desktop/Mobile
      if (ensureSupported != null) {
        final supported = await ensureSupported();
        if (!supported) return;
      }
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withReadStream: false,
        withData: false,
      );

      if (result != null) {
        await _addPickedPlatformFilesToUpload(result.files, targetDir);
      }
    } catch (e) {
      ToastUtil.show('Failed to pick files: $e', title: 'Error'.tr);
    }
  }

  /// [ensureSupported] 可选；在 Web 上若传入，会在用户选完文件夹后再校验（避免 Safari 因异步失去用户手势导致无法打开选择器）。
  Future<void> pickAndUploadFolder(
    String targetDir, {
    Future<bool> Function()? ensureSupported,
  }) async {
    try {
      if (kIsWeb) {
        await _pickAndUploadFolderWeb(
          targetDir,
          ensureSupported: ensureSupported,
        );
        return;
      }

      // Desktop: choose directory and enumerate files
      if (ensureSupported != null) {
        final supported = await ensureSupported();
        if (!supported) return;
      }
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null) return;
      await _addFolderToUpload(dirPath, targetDir);
    } catch (e) {
      ToastUtil.show('Failed to pick folder: $e', title: 'Error'.tr);
    }
  }

  Future<void> uploadDroppedFiles(List<XFile> files, String targetDir) async {
    if (files.isEmpty) return;

    final plainFiles = <XFile>[];
    final folders = <String>[];

    for (final file in files) {
      if (kIsWeb) {
        plainFiles.add(file);
      } else {
        if (await FileSystemEntity.isDirectory(file.path)) {
          folders.add(file.path);
        } else {
          plainFiles.add(file);
        }
      }
    }

    if (plainFiles.isNotEmpty) {
      await _addFilesToUpload(plainFiles.cast<dynamic>().toList(), targetDir);
    }

    for (final folderPath in folders) {
      await _addFolderToUpload(folderPath, targetDir);
    }
  }

  Future<void> uploadDroppedWebFiles(
    List<Map<String, dynamic>> files,
    String targetDir,
  ) async {
    if (files.isEmpty) return;
    debugPrint(
      '[UploadController] uploadDroppedWebFiles: inputFiles=${files.length} targetDir=$targetDir',
    );

    // Group files by root element
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (var item in files) {
      final path = item['path'] as String;
      final root = path.split('/').first;
      groups.putIfAbsent(root, () => []).add(item);
    }
    debugPrint(
      '[UploadController] uploadDroppedWebFiles: groups=${groups.keys.length} keys=${groups.keys.take(5).toList()}',
    );

    for (var root in groups.keys) {
      final groupFiles = groups[root]!;
      // Check if it is a single file (root name matches path)
      if (groupFiles.length == 1 && groupFiles.first['path'] == root) {
        // Single file upload
        await _addFilesToUpload([groupFiles.first], targetDir);
      } else {
        // Folder upload
        await _addWebFolderToUpload(root, groupFiles, targetDir);
      }
    }
  }

  Future<void> _addWebFolderToUpload(
    String rootName,
    List<Map<String, dynamic>> files,
    String targetDir,
  ) async {
    int total = 0;
    final entries = <Map<String, dynamic>>[];

    for (var item in files) {
      final file = item['file'];
      final path = item['path'] as String; // e.g. "Folder/Sub/File.txt"

      final size = UploadWebFileHelper.getFileSize(file);
      final name = UploadWebFileHelper.getFileName(file);

      // Filter ignored files
      if (UploadTransferHelper.shouldIgnore(name)) continue;

      total += size;

      // 'rel' expects the relative path from the root folder
      // path is "Folder/Sub/File.txt"
      // rootName is "Folder"
      // rel should be "Folder/Sub/File.txt" (UploadWebFileHelper behavior)
      // Wait, pickAndUploadFolderWeb uses:
      // rel = WebFileProps(f).webkitRelativePath (e.g. "Folder/Sub/File.txt")
      // entries.add({'ref': file, 'rel': rel, 'size': size});

      entries.add({'ref': file, 'rel': path, 'size': size});
    }

    if (entries.isEmpty) return;

    // Check if this folder is already being uploaded to the same location
    if (UploadTransferHelper.isTaskAlreadyExists(
      tasks,
      rootName,
      targetDir,
      true,
    )) {
      ToastUtil.show("file_allready_in_upload_queue".tr);
      return; // Skip duplicate folder upload
    }

    final taskId =
        "${DateTime.now().millisecondsSinceEpoch.toString()}_$rootName";
    final task = TransferTask(
      id: taskId,
      name: rootName,
      localPath: '',
      remotePath: targetDir,
      type: TransferType.upload,
      totalSize: total,
      status: TransferStatus.pending,
      chunkSize: UploadTransferHelper.calculateChunkSize(total),
      folderCompleted: [],
    );
    task.folderRefs = entries;
    addTaskToList(task);
    ToastUtil.show("file_task_upload_added".tr);
    _processQueue();
  }

  Future<void> _addFilesToUpload(List<dynamic> files, String targetDir) async {
    final newTasks = <TransferTask>[];
    int skippedDup = 0;
    int skippedEmpty = 0;

    for (var fileItem in files) {
      dynamic file;
      String name;
      int size;

      if (fileItem is Map<String, dynamic>) {
        // Web dropped file with path info
        file = fileItem['file'];
        name = UploadWebFileHelper.getFileName(file);
        size = UploadWebFileHelper.getFileSize(file);
      } else {
        file = fileItem;
        if (kIsWeb && file is! XFile) {
          name = UploadWebFileHelper.getFileName(file);
          size = UploadWebFileHelper.getFileSize(file);
        } else {
          // Desktop OR Web XFile
          if (file is XFile) {
            name = file.name;
            size = await file.length();
          } else {
            // Should not happen, but fallback
            continue;
          }
        }
      }

      // Check if file is already being uploaded to the same location
      if (UploadTransferHelper.isFileAlreadyInUpload(tasks, name, targetDir)) {
        ToastUtil.show("file_allready_in_upload_queue".tr);
        skippedDup++;
        continue; // Skip duplicate file
      }

      if (size == 0) {
        // Skip empty files or folders on Web (which often appear as size 0)
        // ToastUtil.show(Get.context!, "跳过空文件或文件夹: $name");
        skippedEmpty++;
        continue;
      }

      final taskId =
          "${DateTime.now().millisecondsSinceEpoch.toString()}_$name";

      _activeFiles[taskId] = file;

      final task = TransferTask(
        id: taskId,
        name: name,
        localPath: kIsWeb ? '' : (file is XFile ? file.path : ''),
        remotePath: targetDir,
        type: TransferType.upload,
        totalSize: size,
        status: TransferStatus.pending,
        chunkSize: UploadTransferHelper.calculateChunkSize(size),
      );
      newTasks.add(task);
    }

    if (newTasks.isNotEmpty) {
      addTaskToList(newTasks);
      ToastUtil.show("file_task_upload_added".tr);
      _processQueue();
    } else {
      debugPrint(
        '[UploadController] _addFilesToUpload: newTasks=0 totalIn=${files.length} skippedDup=$skippedDup skippedEmpty=$skippedEmpty',
      );
    }
  }

  Future<void> _addFolderToUpload(String dirPath, String targetDir) async {
    final root = Directory(dirPath);
    if (!await root.exists()) return;
    final rootName = p.basename(dirPath);
    final normalizedRootName = rootName.replaceAll('\\', '/');

    // Check if this folder is already being uploaded to the same location
    if (UploadTransferHelper.isTaskAlreadyExists(
      tasks,
      rootName,
      targetDir,
      true,
    )) {
      ToastUtil.show("file_allready_in_upload_queue".tr);
      return; // Skip duplicate folder upload
    }

    final entries = <Map<String, dynamic>>[];
    int total = 0;
    await for (var entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final filePath = entity.path;
        // Use cross-platform path handling to get relative path
        final rel = p.relative(filePath, from: dirPath).replaceAll('\\', '/');
        final base = p.basename(rel);
        if (UploadTransferHelper.shouldIgnore(base)) continue;
        final size = await entity.length();
        total += size;
        // Include root folder name in relative path to match web behavior
        final fullRel = rel.isEmpty
            ? normalizedRootName
            : '$normalizedRootName/$rel';
        entries.add({'ref': XFile(filePath), 'rel': fullRel, 'size': size});
      }
    }
    if (entries.isEmpty) return;

    final taskId =
        "${DateTime.now().millisecondsSinceEpoch.toString()}_$rootName";
    final task = TransferTask(
      id: taskId,
      name: rootName,
      localPath: dirPath,
      remotePath: targetDir,
      type: TransferType.upload,
      totalSize: total,
      status: TransferStatus.pending,
      chunkSize: UploadTransferHelper.calculateChunkSize(total),
      folderCompleted: [],
    );
    task.folderRefs = entries;
    addTaskToList(task);
    _processQueue();
    ToastUtil.show("file_task_upload_added".tr);
  }

  Future<void> _pickAndUploadFolderWeb(
    String targetDir, {
    Future<bool> Function()? ensureSupported,
  }) async {
    final files = await UploadWebFileHelper.pickDirectoryFiles();
    if (files.isEmpty) return;
    // Safari: 选文件夹后的延续有时不执行，放到下一帧跑确保稳定触发上传
    final done = Completer<void>();
    void run() async {
      try {
        if (ensureSupported != null) {
          final supported = await ensureSupported();
          if (!supported) {
            done.complete();
            return;
          }
        }
        await _pickAndUploadFolderWebContinue(files, targetDir);
      } catch (e) {
        ToastUtil.show('Failed to pick folder: $e', title: 'Error'.tr);
      } finally {
        if (!done.isCompleted) done.complete();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => run());
    await done.future;
  }

  Future<void> _pickAndUploadFolderWebContinue(
    List<dynamic> files,
    String targetDir,
  ) async {
    int total = 0;
    String rootName = 'Folder';
    final entries = <Map<String, dynamic>>[];
    for (var file in files) {
      final size = UploadWebFileHelper.getFileSize(file);
      final rel = UploadWebFileHelper.getRelativePath(file);
      final base = rel.contains('/')
          ? rel.split('/').last
          : UploadWebFileHelper.getFileName(file);
      if (UploadTransferHelper.shouldIgnore(base)) continue;
      total += size;
      if (rel.contains('/')) {
        rootName = rel.split('/').first;
      } else {
        rootName = UploadWebFileHelper.getFileName(file);
      }
      entries.add({'ref': file, 'rel': rel, 'size': size});
    }

    // Check if this folder is already being uploaded to the same location
    if (UploadTransferHelper.isTaskAlreadyExists(
      tasks,
      rootName,
      targetDir,
      true,
    )) {
      ToastUtil.show("file_allready_in_upload_queue".tr);
      return; // Skip duplicate folder upload
    }

    final taskId =
        "${DateTime.now().millisecondsSinceEpoch.toString()}_$rootName";
    final task = TransferTask(
      id: taskId,
      name: rootName,
      localPath: '',
      remotePath: targetDir,
      type: TransferType.upload,
      totalSize: total,
      status: TransferStatus.pending,
      chunkSize: UploadTransferHelper.calculateChunkSize(total),
      folderCompleted: [],
    );
    task.folderRefs = entries;
    addTaskToList(task);
    ToastUtil.show("file_task_upload_added".tr);
    _processQueue();
  }

  void startTask(TransferTask task) {
    if (task.status == TransferStatus.uploading) return;
    _cancelTokens[task.id] = dio.CancelToken();
    task.status = TransferStatus.pending;
    task.error = null;
    tasks.refresh();
    _processQueue();
  }

  void pauseTask(TransferTask task) {
    if (task.status == TransferStatus.uploading ||
        task.status == TransferStatus.pending) {
      _cancelTokens[task.id]?.cancel();
      _processingIds.remove(task.id);
    }
    task.status = TransferStatus.paused;
    tasks.refresh();
    _processQueue(); // Start others
  }

  void pauseAll() {
    for (var task in tasks) {
      if (task.status == TransferStatus.uploading ||
          task.status == TransferStatus.pending) {
        _cancelTokens[task.id]?.cancel();
        _processingIds.remove(task.id);
        task.status = TransferStatus.paused;
      }
    }
    tasks.refresh();
    _processQueue();
  }

  void startAll() {
    for (var task in tasks) {
      if (task.status == TransferStatus.paused ||
          task.status == TransferStatus.error) {
        task.status = TransferStatus.pending;
      }
    }
    tasks.refresh();
    _processQueue();
  }

  void deleteTask(TransferTask task) {
    pauseTask(task);
    tasks.remove(task);
    final removed = _activeFiles.remove(task.id);
    if (!kIsWeb && removed is XFile) {
      unawaited(
        UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(removed.path),
      );
    }
    _cancelTokens.remove(task.id);
  }

  void clearAll() {
    for (final task in tasks) {
      _cancelTokens[task.id]?.cancel();
    }
    _processingIds.clear();
    _cancelTokens.clear();
    tasks.clear();
    if (!kIsWeb) {
      final removed = _activeFiles.values.toList(growable: false);
      for (final v in removed) {
        if (v is XFile) {
          unawaited(
            UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(v.path),
          );
        }
      }
    }
    _activeFiles.clear();
  }

  void clearCompleted() {
    final completed = tasks
        .where((t) => t.status == TransferStatus.completed)
        .toList();
    for (var task in completed) {
      final removed = _activeFiles.remove(task.id);
      if (!kIsWeb && removed is XFile) {
        unawaited(
          UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(removed.path),
        );
      }
    }
    tasks.removeWhere((t) => t.status == TransferStatus.completed);
  }

  void clearError() {
    final errorTasks = tasks
        .where((t) => t.status == TransferStatus.error)
        .toList();
    for (var task in errorTasks) {
      final removed = _activeFiles.remove(task.id);
      if (!kIsWeb && removed is XFile) {
        unawaited(
          UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(removed.path),
        );
      }
    }
    tasks.removeWhere((t) => t.status == TransferStatus.error);
  }

  void clearWaiting() {
    final waitingTasks = tasks
        .where((t) => t.status == TransferStatus.pending)
        .toList();
    for (var task in waitingTasks) {
      final removed = _activeFiles.remove(task.id);
      if (!kIsWeb && removed is XFile) {
        unawaited(
          UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(removed.path),
        );
      }
    }
    tasks.removeWhere((t) => t.status == TransferStatus.pending);
  }

  // --- Queue Processing ---

  Future<void> _processQueue() async {
    if (_queueProcessing) return;
    _queueProcessing = true;
    try {
      while (_processingIds.length < maxConcurrent.value) {
        final pending = tasks.firstWhereOrNull(
          (t) =>
              t.status == TransferStatus.pending &&
              !_processingIds.contains(t.id),
        );
        if (pending == null) {
          final hasActive = tasks.any(
            (t) =>
                t.status == TransferStatus.pending ||
                t.status == TransferStatus.uploading,
          );
          if (!hasActive) {
            unawaited(
              TransferWorkNotificationHub.instance.uploadWorkForceCancel(),
            );
          }
          return;
        }
        if (pending.folderRefs != null) {
          unawaited(_uploader.uploadFolder(pending).whenComplete(_processQueue));
        } else {
          unawaited(_uploader.uploadFile(pending).whenComplete(_processQueue));
        }
      }
    } finally {
      _queueProcessing = false;
    }
  }

  // Format bytes to human readable format
  String formatBytes(int bytes) {
    return UploadTransferHelper.formatBytes(bytes);
  }
}
