import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/device_utils.dart';
import '../../utils/cache_manager.dart';

/// 传输类后台任务共用本地通知：下载 / 上传 / 相册备份各最多一条， refcount 为 0 时取消。
class TransferWorkNotificationHub {
  TransferWorkNotificationHub._();
  static final TransferWorkNotificationHub instance =
      TransferWorkNotificationHub._();

  static const int _idDownload = 9201;
  static const int _idUpload = 9202;
  static const int _idBackup = 9203;

  static const String _chDownload = 'nascab_work_download';
  static const String _chUpload = 'nascab_work_upload';
  static const String _chBackup = 'nascab_work_backup';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initFuture;
  bool _inited = false;

  int _downloadRef = 0;
  int _uploadRef = 0;
  int _backupRef = 0;

  DateTime _lastDownloadNotify = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUploadNotify = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastBackupNotify = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _throttle = Duration(milliseconds: 700);

  bool get _active => DeviceUtils.isMobile && !kIsWeb;

  static const String _kIosNotificationPrompted =
      'transfer_ios_notification_prompted';

  Future<void> ensureInitialized() async {
    if (!_active) return;
    _initFuture ??= _init();
    await _initFuture;
  }

  Future<void> _init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      for (final ch in <AndroidNotificationChannel>[
        AndroidNotificationChannel(
          _chDownload,
          'transfer_notification_downloading_title'.tr,
          description: 'transfer_notification_downloading_title'.tr,
          importance: Importance.low,
        ),
        AndroidNotificationChannel(
          _chUpload,
          'transfer_notification_uploading_title'.tr,
          description: 'transfer_notification_uploading_title'.tr,
          importance: Importance.low,
        ),
        AndroidNotificationChannel(
          _chBackup,
          'transfer_notification_photo_backup_title'.tr,
          description: 'transfer_notification_photo_backup_title'.tr,
          importance: Importance.low,
        ),
      ]) {
        await androidImpl?.createNotificationChannel(ch);
      }
    }
    _inited = true;
  }

  Future<bool> _notificationsAllowed() async {
    if (!_active) return false;
    await ensureInitialized();
    if (Platform.isAndroid) {
      final st = await Permission.notification.status;
      if (st.isDenied || st.isPermanentlyDenied) {
        await Permission.notification.request();
      }
      return await Permission.notification.isGranted;
    }
    if (Platform.isIOS) {
      final st = await Permission.notification.status;
      if (st.isGranted) return true;
      if (st.isPermanentlyDenied || st.isRestricted) {
        try {
          await CacheManager().setBool(_kIosNotificationPrompted, true);
        } catch (_) {}
        return false;
      }
      if (st.isDenied) {
        final prompted = CacheManager().getBool(_kIosNotificationPrompted);
        if (prompted == true) return false;
        final res = await Permission.notification.request();
        if (res.isGranted) return true;
        try {
          await CacheManager().setBool(_kIosNotificationPrompted, true);
        } catch (_) {}
        return false;
      }
      return false;
    }
    return true;
  }

  Future<void> _showOrUpdate({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    int? progressPercent,
  }) async {
    if (!await _notificationsAllowed()) return;

    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
      showProgress: progressPercent != null,
      maxProgress: 100,
      progress: progressPercent?.clamp(0, 100) ?? 0,
      indeterminate: progressPercent == null,
    );

    const darwin = DarwinNotificationDetails(
      presentSound: false,
      presentBadge: false,
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android, iOS: darwin),
    );
  }

  Future<void> _cancel(int id) async {
    if (!_active) return;
    await ensureInitialized();
    await _plugin.cancel(id: id);
  }

  // --- Download ---

  Future<void> downloadWorkBegan() async {
    if (!_active) return;
    _downloadRef += 1;
    final shouldShow = _downloadRef == 1;
    await ensureInitialized();
    if (!shouldShow || _downloadRef <= 0) return;
    if (!await _notificationsAllowed()) return;
    await _showOrUpdate(
      id: _idDownload,
      channelId: _chDownload,
      channelName: 'transfer_notification_downloading_title'.tr,
      channelDescription: 'transfer_notification_downloading_title'.tr,
      title: 'transfer_notification_downloading_title'.tr,
      body: 'transfer_notification_downloading_body'.trParams({
        'displayName': '…',
        'progress': '',
        'networkSpeed': '',
      }),
      progressPercent: null,
    );
  }

  Future<void> downloadWorkEnded() async {
    if (!_active) return;
    _downloadRef = (_downloadRef - 1).clamp(0, 1 << 20);
    if (_downloadRef == 0) {
      await _cancel(_idDownload);
    }
  }

  Future<void> downloadProgressThrottled({
    required String displayName,
    int? percent,
  }) async {
    if (!_active || _downloadRef <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastDownloadNotify) < _throttle) return;
    _lastDownloadNotify = now;
    final progressText = percent != null ? '$percent%' : '…';
    if (!await _notificationsAllowed()) return;
    await _showOrUpdate(
      id: _idDownload,
      channelId: _chDownload,
      channelName: 'transfer_notification_downloading_title'.tr,
      channelDescription: 'transfer_notification_downloading_title'.tr,
      title: 'transfer_notification_downloading_title'.tr,
      body: 'transfer_notification_downloading_body'.trParams({
        'displayName': displayName,
        'progress': progressText,
        'networkSpeed': '',
      }),
      progressPercent: percent,
    );
  }

  // --- Upload ---

  Future<void> uploadWorkBegan() async {
    if (!_active) return;
    _uploadRef += 1;
    final shouldShow = _uploadRef == 1;
    await ensureInitialized();
    if (!shouldShow || _uploadRef <= 0) return;
    if (!await _notificationsAllowed()) return;
    await _showOrUpdate(
      id: _idUpload,
      channelId: _chUpload,
      channelName: 'transfer_notification_uploading_title'.tr,
      channelDescription: 'transfer_notification_uploading_title'.tr,
      title: 'transfer_notification_uploading_title'.tr,
      body: 'transfer_notification_uploading_body'.trParams({
        'displayName': '…',
        'progress': '',
        'networkSpeed': '',
      }),
      progressPercent: null,
    );
  }

  Future<void> uploadWorkEnded() async {
    if (!_active) return;
    _uploadRef = (_uploadRef - 1).clamp(0, 1 << 20);
    if (_uploadRef == 0) {
      await _cancel(_idUpload);
    }
  }

  Future<void> uploadWorkForceCancel() async {
    if (!_active) return;
    _uploadRef = 0;
    await _cancel(_idUpload);
  }

  Future<void> uploadProgressThrottled({
    required String displayName,
    required int processed,
    required int total,
  }) async {
    if (!_active || _uploadRef <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastUploadNotify) < _throttle) return;
    _lastUploadNotify = now;
    int? pct;
    if (total > 0) {
      pct = ((processed / total) * 100).floor().clamp(0, 100);
    }
    final progressText = pct != null ? '$pct%' : '…';
    if (!await _notificationsAllowed()) return;
    await _showOrUpdate(
      id: _idUpload,
      channelId: _chUpload,
      channelName: 'transfer_notification_uploading_title'.tr,
      channelDescription: 'transfer_notification_uploading_title'.tr,
      title: 'transfer_notification_uploading_title'.tr,
      body: 'transfer_notification_uploading_body'.trParams({
        'displayName': displayName,
        'progress': progressText,
        'networkSpeed': '',
      }),
      progressPercent: pct,
    );
  }

  // --- Photo backup ---

  Future<void> backupWorkBegan() async {
    if (!_active) return;
    _backupRef += 1;
    final shouldShow = _backupRef == 1;
    await ensureInitialized();
    if (!shouldShow || _backupRef <= 0) return;
    if (!await _notificationsAllowed()) return;
    await _showOrUpdate(
      id: _idBackup,
      channelId: _chBackup,
      channelName: 'transfer_notification_photo_backup_title'.tr,
      channelDescription: 'transfer_notification_photo_backup_title'.tr,
      title: 'transfer_notification_photo_backup_title'.tr,
      body: 'transfer_notification_photo_backup_body'.trParams({
        'currentFile': '…',
        'progress': '',
      }),
      progressPercent: null,
    );
  }

  Future<void> backupWorkEnded() async {
    if (!_active) return;
    _backupRef = (_backupRef - 1).clamp(0, 1 << 20);
    if (_backupRef == 0) {
      await _cancel(_idBackup);
    }
  }

  /// 刷新相册备份通知文案（内部节流）；[progress] 为 0~1，与 [PhotoBackupRuntime.progress] 一致。
  void photoBackupProgressThrottled({
    required String currentFile,
    double? progress,
    required int doneFiles,
    required int totalFiles,
  }) {
    if (!_active || _backupRef <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastBackupNotify) < _throttle) return;
    _lastBackupNotify = now;
    String progressText;
    if (progress != null) {
      progressText = '${(progress * 100).floor()}%';
    } else if (totalFiles > 0) {
      progressText = '$doneFiles/$totalFiles';
    } else {
      progressText = '';
    }
    final body = 'transfer_notification_photo_backup_body'.trParams({
      'currentFile': currentFile.trim().isEmpty ? '…' : currentFile,
      'progress': progressText,
    });
    unawaited(
      _showOrUpdate(
        id: _idBackup,
        channelId: _chBackup,
        channelName: 'transfer_notification_photo_backup_title'.tr,
        channelDescription: 'transfer_notification_photo_backup_title'.tr,
        title: 'transfer_notification_photo_backup_title'.tr,
        body: body,
        progressPercent: progress != null
            ? (progress * 100).floor().clamp(0, 100)
            : null,
      ),
    );
  }
}
