import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/web/web_file_download_stub.dart'
    if (dart.library.html) '../../../core/web/web_file_download_web.dart'
    as web_file_download;
import '../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../core/api/p2p_rtc_web.dart';

import '../../home/views/app_home_controller.dart';
import '../../home/views/pc_home_controller.dart';
import 'task_center_controller.dart';
import '../../../core/api/api_controller.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/file_util.dart';
import '../../../utils/dialog_util.dart';
import '../models/transfer_task.dart';
import '../../files/service/file_api_service.dart';
import '../../files/service/file_stats_service.dart';
import '../../base/components/custom_checkbox.dart';
import '../../../utils/cache_manager.dart';
import '../views/download/download_center/app_download_center_view.dart';
import '../storage/download_history_storage.dart';
import '../../../utils/http_util.dart';
import '../../../core/api/dio_bad_certificate_compat.dart';
import '../models/nascab_transfer_downloader_types.dart';
import '../../../core/notification/transfer_work_notification_hub.dart';

part 'download_parts/download_state_mixin.dart';
part 'download_parts/download_dialog_mixin.dart';
part 'download_parts/download_web_mixin.dart';
part 'download_parts/desktop_download_worker_mixin.dart';
part 'download_parts/download_worker_mixin.dart';
part 'download_parts/download_action_mixin.dart';

Map<String, String>? _buildAuthHeadersForUrl(
  String url, {
  Map<String, String>? extraHeaders,
}) {
  final headers = <String, String>{...?extraHeaders};
  final token = (ApiController.instance.accessToken ?? '').trim();
  final requestUri = Uri.tryParse(url);
  final baseUri = Uri.tryParse(ApiController.instance.baseUrl);
  final isSameOrigin =
      requestUri != null &&
      baseUri != null &&
      requestUri.scheme == baseUri.scheme &&
      requestUri.host == baseUri.host &&
      requestUri.port == baseUri.port;
  if (isSameOrigin && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers.isEmpty ? null : headers;
}

/// 下载控制器
/// 负责处理所有的下载逻辑，包括Web、移动端和桌面端
/// 集成了多个Mixin以分散职责：
/// - DownloadStateMixin: 状态管理
/// - DownloadDialogMixin: UI对话框
/// - DownloadWebMixin: Web下载
/// - DesktopDownloadWorkerMixin: Dio 直连下载（桌面与移动端共用）
/// - DownloadWorkerMixin: 通用下载Worker
/// - DownloadActionMixin: 用户操作（暂停、删除等）
class DownloadController extends GetxController
    with
        DownloadStateMixin,
        DownloadDialogMixin,
        DownloadWebMixin,
        DesktopDownloadWorkerMixin,
        DownloadWorkerMixin,
        DownloadActionMixin {
  @override
  void onInit() {
    super.onInit();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ensureNotificationPermission());
      });
    }
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

  @override
  void onClose() {
    statsService?.close();
    super.onClose();
  }

  /// 处理下载请求
  /// [paths] 远程文件路径列表
  /// [remoteIsDirectoryHint] 与 [paths] 等长时生效：`true` 目录、`false` 文件、`null` 该项未知。
  Future<void> handleDownload(
    List<String> paths, {
    List<bool?>? remoteIsDirectoryHint,
  }) async {
    if (paths.isEmpty) return;

    if (kIsWeb) {
      await downloadWeb(paths);
    } else {
      await downloadNonWeb(
        paths,
        remoteIsDirectoryHint: remoteIsDirectoryHint,
      );
    }
  }

  /// 处理非Web端下载（移动端/桌面端）
  Future<void> downloadNonWeb(
    List<String> paths, {
    List<bool?>? remoteIsDirectoryHint,
  }) async {
    String? saveDir;
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动端默认保存到文档目录下的 NasCabDownload
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = p.join(appDir.path, 'NasCabDownload');
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      // 桌面端弹出选择框
      calculateStats(paths);
      final result = await Get.dialog<String>(
        buildDownloadConfirmDialog(paths),
      );
      if (result != null) {
        saveDir = result;
      } else {
        return;
      }
    }

    // 再次检查写入权限
    try {
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (Platform.isMacOS) {
        final tempFile = File(p.join(saveDir, '.nascab_perm_check'));
        tempFile.writeAsStringSync('');
        tempFile.deleteSync();
      }
    } catch (e) {
      ToastUtil.show('permission_denied_select_again'.tr);
      // 清除无效的缓存路径
      if (Platform.isMacOS) {
        CacheManager().remove('last_download_path');
      }
      return;
    }

    addTasks(
      paths,
      saveDir,
      remoteIsDirectoryHint: remoteIsDirectoryHint,
    );
  }

  Future<void> handlePhotoDownload({
    required String albumType,
    required List<int> ids,
  }) async {
    final type = albumType.toLowerCase();
    final uniqueIds = ids.where((e) => e > 0).toSet().toList()..sort();
    if (uniqueIds.isEmpty) return;

    if (kIsWeb) {
      final url = type == 'face'
          ? ApiController.instance.getFaceDownloadUrl(uniqueIds)
          : ApiController.instance.getAlbumDownloadUrl(uniqueIds);
      await handleDownload([url]);
      return;
    }

    String? saveDir;
    if (Platform.isAndroid || Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = p.join(appDir.path, 'NasCabDownload');
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    statsService?.close();
    statsSize.value = 0;
    statsCount.value = 0;
    isCalculatingStats.value = true;

    final infoList = <Map<String, dynamic>>[];
    final dialogNames = <String>[];
    int totalSize = 0;
    int totalCount = 0;

    for (final id in uniqueIds) {
      final info = await _fetchPhotoDownloadInfo(type: type, id: id);
      if (info == null) continue;
      infoList.add(info);

      final name = (info['name'] ?? '').toString();
      if (name.isNotEmpty) {
        dialogNames.add(name);
      } else {
        dialogNames.add('${type}_$id');
      }

      final sizeRaw = info['totalSize'];
      final countRaw = info['count'];
      if (sizeRaw is num) totalSize += sizeRaw.toInt();
      if (countRaw is num) totalCount += countRaw.toInt();
    }

    statsSize.value = totalSize;
    statsCount.value = totalCount;
    isCalculatingStats.value = false;

    if (infoList.isEmpty) {
      ToastUtil.show('network_failure'.tr);
      return;
    }

    if (saveDir == null) {
      final result = await Get.dialog<String>(
        buildDownloadConfirmDialog(dialogNames.isEmpty ? [type] : dialogNames),
      );
      if (result != null) {
        saveDir = result;
      } else {
        return;
      }
    }

    try {
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      if (Platform.isMacOS) {
        final tempFile = File(p.join(saveDir, '.nascab_perm_check'));
        tempFile.writeAsStringSync('');
        tempFile.deleteSync();
      }
    } catch (e) {
      ToastUtil.show('permission_denied_select_again'.tr);
      if (Platform.isMacOS) {
        CacheManager().remove('last_download_path');
      }
      return;
    }

    for (final info in infoList) {
      final idRaw = info['albumId'] ?? info['album_id'] ?? info['id'];
      final albumId = idRaw is num
          ? idRaw.toInt()
          : int.tryParse('$idRaw') ?? 0;
      final nameRaw = (info['name'] ?? '').toString();
      final name = nameRaw.isNotEmpty ? nameRaw : '${type}_$albumId';
      final baseLocal = p.join(saveDir, name);

      final items = info['items'] as List?;
      final refs = <Map<String, dynamic>>[];
      if (items != null) {
        for (final raw in items) {
          if (raw is Map) {
            refs.add(Map<String, dynamic>.from(raw));
          }
        }
      }

      final sizeRaw = info['totalSize'];
      final taskTotal = sizeRaw is num ? sizeRaw.toInt() : 0;

      final task = TransferTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_${type}_$albumId',
        name: name,
        localPath: baseLocal,
        remotePath: 'photo:$type:$albumId',
        type: TransferType.download,
        status: TransferStatus.pending,
        totalSize: taskTotal,
      );
      task.folderRefs = refs;

      tasks.add(task);
      processTask(task);
    }

    ToastUtil.show('task_added'.tr);
    if (Platform.isAndroid || Platform.isIOS) {
      Get.to(() => const AppDownloadCenterView());
      return;
    }

    if (Get.isRegistered<PcHomeController>()) {
      final home = PcHomeController.instance;
      final taskCenter = Get.isRegistered<TaskCenterController>()
          ? TaskCenterController.to
          : Get.put(TaskCenterController());
      taskCenter.jumpToPage(1);
      home.openApp(
        windowId: 'task_center',
        viewBuilder: home.builtinAppViewBuilder('task_center'),
        title: 'app_task_center'.tr,
        icon: home.buildAppIcon('task_center'),
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchPhotoDownloadInfo({
    required String type,
    required int id,
  }) async {
    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;
    final url = '$baseUrl/api/photo/download/info';
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final res = await HttpUtil.apiPost<Map<String, dynamic>>(
      url,
      body: jsonEncode({'albumType': type, 'albumId': id}),
      headers: headers,
    );
    if (!res.success || res.data == null) return null;
    return Map<String, dynamic>.from(res.data!);
  }
}
