import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:crypto/crypto.dart';
import '../../models/transfer_task.dart';

enum SmartUploadDecision { upload, skip, error }

/// 传输辅助工具类
/// 提供文件上传过程中的各种辅助功能
class UploadTransferHelper {
  /// 从错误中获取服务器消息
  /// 参数：
  /// - e: 错误对象
  /// 返回：
  /// - 格式化后的错误消息
  static String getServerMessage(dynamic e) {
    if (e is dio.DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return getDisplayMessage(e.message ?? e.toString());
    }
    if (e is String) return getDisplayMessage(e);
    return getDisplayMessage(e.toString());
  }

  /// 从可能为 JSON 的字符串中提取用于展示的错误信息。
  /// 若为 {"success":false,"code":"xxx","message":"xxx"} 则返回 message 字段，否则返回原字符串。
  static String getDisplayMessage(String? error) {
    if (error == null || error.trim().isEmpty) return '';
    final trimmed = error.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['message'] != null) {
        final msg = decoded['message'].toString().trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return trimmed;
  }

  /// 检查文件是否应该被忽略
  /// 用于过滤系统文件、隐藏文件等不需要上传的文件
  /// 参数：
  /// - name: 文件名
  /// 返回值：
  /// - true: 应该忽略该文件
  /// - false: 不应该忽略该文件
  static bool shouldIgnore(String name) {
    final lower = name.toLowerCase(); // 转换为小写便于比较

    // 忽略常见的系统文件
    if (lower == '.ds_store' || // macOS系统文件
        lower == 'thumbs.db' || // Windows系统文件
        lower == 'desktop.ini') {
      // Windows系统文件
      return true;
    }

    // 忽略macOS隐藏文件（以._开头的文件）
    if (lower.startsWith('._')) return true;

    // 忽略macOS系统目录
    if (lower == '.spotlight-v100' || // macOS搜索索引
        lower == '.trashes' || // macOS回收站
        lower == '.fseventsd') {
      // macOS文件系统事件目录
      return true;
    }

    // 其他文件不忽略
    return false;
  }

  /// 检查队列中是否已存在类似的上传任务（未完成状态）
  /// 参数：
  /// - tasks: 任务列表
  /// - name: 任务名称（文件名或文件夹名）
  /// - remotePath: 远程目标路径
  /// - isFolder: 是否为文件夹上传
  /// 返回值：
  /// - true: 已存在类似任务
  /// - false: 不存在类似任务
  static bool isTaskAlreadyExists(
    List<TransferTask> tasks,
    String name,
    String remotePath,
    bool isFolder,
  ) {
    return tasks.any((task) {
      // 跳过已完成的任务
      if (task.status == TransferStatus.completed) return false;

      // 对于单文件上传任务
      if (!isFolder && task.folderRefs == null) {
        // 检查文件名和远程路径是否完全匹配
        return task.name == name && task.remotePath == remotePath;
      }

      // 对于文件夹上传任务
      if (isFolder && task.folderRefs != null) {
        // 检查文件夹名称和远程路径是否完全匹配
        return task.name == name && task.remotePath == remotePath;
      }

      // 其他情况视为不存在
      return false;
    });
  }

  /// 检查特定文件是否已经在上传队列中
  /// 用于避免同一文件重复上传到相同位置
  /// 参数：
  /// - tasks: 任务列表
  /// - fileName: 文件名
  /// - remotePath: 远程目标路径
  /// 返回值：
  /// - true: 文件已在上传队列中
  /// - false: 文件不在上传队列中
  static bool isFileAlreadyInUpload(
    List<TransferTask> tasks,
    String fileName,
    String remotePath,
  ) {
    // 遍历所有任务
    for (var task in tasks) {
      // 跳过已完成的任务
      if (task.status == TransferStatus.completed) continue;

      // 检查单文件上传任务
      if (task.folderRefs == null) {
        // 检查文件名和远程路径是否匹配
        if (task.name == fileName && task.remotePath == remotePath) {
          return true;
        }
      }
      // 检查文件夹上传任务
      else {
        // 遍历文件夹中的所有文件条目
        for (var entry in task.folderRefs!) {
          final rel = entry['rel'] as String; // 相对路径
          final entryFileName = rel.split('/').last; // 提取文件名
          final entryRemotePath = task.remotePath; // 远程路径
          // 检查文件名和远程路径是否匹配
          if (entryFileName == fileName && entryRemotePath == remotePath) {
            return true;
          }
        }
      }
    }
    // 遍历完成，未找到匹配的文件
    return false;
  }

  /// 根据文件大小计算合适的分块大小
  /// 用于大文件上传时分块处理
  /// 参数：
  /// - fileSize: 文件大小（字节）
  /// 返回值：合适的分块大小（字节）
  static int calculateChunkSize(int fileSize) {
    // 根据文件大小动态调整分块大小
    if (fileSize < 200 * 1024 * 1024) {
      // 小于200MB
      return 5 * 1024 * 1024; // 5MB分块
    } else if (fileSize < 500 * 1024 * 1024) {
      // 200MB到500MB
      return 10 * 1024 * 1024; // 10MB分块
    } else if (fileSize < 1000 * 1024 * 1024) {
      // 500MB到1GB
      return 15 * 1024 * 1024; // 15MB分块
    } else if (fileSize < 2000 * 1024 * 1024) {
      // 1GB到2GB
      return 20 * 1024 * 1024; // 20MB分块
    } else if (fileSize < 3000 * 1024 * 1024) {
      // 2GB到3GB
      return 25 * 1024 * 1024; // 25MB分块
    } else {
      // 大于等于3GB
      return 30 * 1024 * 1024; // 30MB分块
    }
  }

  /// 检查错误是否为文件已存在错误
  /// 用于处理上传过程中遇到的文件冲突
  /// 参数：
  /// - e: 错误对象
  /// 返回值：
  /// - true: 是文件已存在错误
  /// - false: 不是文件已存在错误
  static bool isFileExistsError(dynamic e) {
    if (e is dio.DioException) {
      final status = e.response?.statusCode;
      if (status == 409) return true;

      final data = e.response?.data;
      if (data is Map) {
        final code = data['code']?.toString();
        if (code != null) {
          final u = code.toUpperCase();
          if (u.contains('EXIST')) return true;
        }
        final msg = data['message']?.toString();
        if (msg != null) {
          final l = msg.toLowerCase();
          if (l.contains('exist') || msg.contains('已存在')) return true;
        }
      }
      final m = e.message ?? '';
      if (m.toLowerCase().contains('exist')) return true;
    }
    if (e is String) {
      final l = e.toLowerCase();
      if (l.contains('exist') || e.contains('已存在')) return true;
    }
    return false;
  }

  static SmartUploadDecision decideSmartUpload({
    required bool remoteExists,
    required bool remoteIsFile,
    required int? remoteSize,
    required int localSize,
    required bool md5Equal,
  }) {
    if (!remoteExists) return SmartUploadDecision.upload;
    if (!remoteIsFile) return SmartUploadDecision.error;
    if (remoteSize == null) return SmartUploadDecision.upload;
    if (remoteSize != localSize) return SmartUploadDecision.upload;
    return md5Equal ? SmartUploadDecision.skip : SmartUploadDecision.upload;
  }

  static Future<String> computeFileMd5(
    String filePath, {
    int? fileSize,
    int thresholdBytes = 50 * 1024 * 1024,
    int chunkSizeBytes = 1024 * 1024,
  }) async {
    final size = fileSize ?? await File(filePath).length();
    if (size < thresholdBytes) {
      return await _computeFullMd5(filePath);
    }
    return await _computeHeadTailMd5(filePath, size, chunkSizeBytes);
  }

  static Future<String> _computeFullMd5(String filePath) async {
    final digest = await md5.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  static Future<String> _computeHeadTailMd5(
    String filePath,
    int fileSize,
    int chunkSizeBytes,
  ) async {
    final headLen = fileSize < chunkSizeBytes ? fileSize : chunkSizeBytes;
    final tailLen = fileSize < chunkSizeBytes ? fileSize : chunkSizeBytes;

    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      final head = await raf.read(headLen);
      await raf.setPosition(fileSize - tailLen);
      final tail = await raf.read(tailLen);
      final digest = md5.convert(<int>[...head, ...tail]);
      return digest.toString();
    } finally {
      await raf.close();
    }
  }

  /// 将字节大小格式化为人类可读的字符串
  /// 用于显示文件大小，如 "1.5 MB"
  /// 参数：
  /// - bytes: 字节数
  /// 返回值：格式化后的字符串
  static String formatBytes(int bytes) {
    if (bytes <= 0) return "0 B"; // 零字节显示为 "0 B"

    // 定义字节单位后缀
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0; // 单位索引
    double d = bytes.toDouble(); // 转换为双精度浮点数便于计算

    // 计算合适的单位
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024; // 转换为更大的单位
      i++; // 递增单位索引
    }

    // 格式化为带一位小数的字符串并添加单位后缀
    return '${d.toStringAsFixed(1)}${suffixes[i]}';
  }
}
