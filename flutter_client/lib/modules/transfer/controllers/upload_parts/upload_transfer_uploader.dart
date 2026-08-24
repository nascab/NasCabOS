import 'dart:async';
import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';

import '../../models/transfer_task.dart';
import 'upload_file_handler.dart';
import 'upload_folder_handler.dart';

/// 文件上传协调器
/// 负责协调单个文件和文件夹的上传，是上传功能的入口点
/// - 管理单个文件上传处理器和文件夹上传处理器
/// - 提供统一的上传接口
/// - 处理上传任务的分发和调度
class UploadTransferUploader {
  /// 单个文件上传处理器
  late final UploadFileHandler _fileUploadHandler;

  /// 文件夹上传处理器
  late final UploadFolderHandler _folderUploadHandler;

  /// 构造函数
  /// 参数：
  /// - activeFiles: 文件引用映射，存储任务ID到文件对象的映射
  /// - processingIds: 正在处理的任务ID列表
  /// - cancelTokens: 取消令牌映射，用于取消上传任务
  /// - dio: Dio实例，用于发送HTTP请求
  /// - tasks: 任务列表（响应式）
  /// - nameStrategy: 命名策略（响应式），用于处理同名文件冲突
  /// - refreshThrottled: 节流刷新函数，用于避免频繁UI更新
  UploadTransferUploader(
    final Map<String, dynamic> activeFiles,
    final List<String> processingIds,
    final Map<String, dio.CancelToken> cancelTokens,
    final dio.Dio dio,
    final RxList<TransferTask> tasks,
    final RxString nameStrategy,
    final RxString saveType,
    final Function refreshThrottled,
  ) {
    // 初始化单个文件上传处理器
    _fileUploadHandler = UploadFileHandler(
      activeFiles,
      processingIds,
      cancelTokens,
      dio,
      tasks,
      nameStrategy,
      saveType,
      refreshThrottled,
    );

    // 初始化文件夹上传处理器
    _folderUploadHandler = UploadFolderHandler(
      processingIds,
      cancelTokens,
      dio,
      tasks,
      nameStrategy,
      saveType,
      refreshThrottled,
    );
  }

  /// 上传单个文件
  /// 参数：
  /// - task: 传输任务对象
  Future<void> uploadFile(TransferTask task) async {
    // 调用单个文件上传处理器处理上传任务
    await _fileUploadHandler.uploadFile(task);
  }

  /// 上传文件夹
  /// 参数：
  /// - task: 传输任务对象
  Future<void> uploadFolder(TransferTask task) async {
    // 调用文件夹上传处理器处理上传任务
    await _folderUploadHandler.uploadFolder(task);
  }
}
