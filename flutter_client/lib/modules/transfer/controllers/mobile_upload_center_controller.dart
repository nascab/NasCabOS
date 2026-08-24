import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/api/api_controller.dart';
import '../../../utils/cache_manager.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../files/service/file_api_service.dart';
import '../../files/views/folder_picker_dialog.dart';

class MobileUploadCenterController extends GetxController {
  MobileUploadCenterController({this.bootstrapTargetDir});

  /// 从文件浏览器等入口带入的目录；优先于本地缓存加载，且与 [_loadCachedTargetDir] 互斥，避免异步竞态覆盖。
  final String? bootstrapTargetDir;

  static const String targetDirCacheKey = 'app_upload_center_target_dir';
  static const String uploadLivePhotoVideoCacheKey =
      'app_upload_center_upload_livephoto_video';

  final targetDir = ''.obs;
  final checkingTargetDir = false.obs;
  final uploadLivePhotoVideo = false.obs;

  String _targetDirCacheKey() {
    final serverId = Get.isRegistered<ApiController>()
        ? Get.find<ApiController>().state.serverId.trim()
        : '';
    return serverId.isEmpty
        ? targetDirCacheKey
        : '${targetDirCacheKey}_$serverId';
  }

  @override
  void onInit() {
    super.onInit();
    _loadCachedOptions();
    final boot = bootstrapTargetDir?.trim() ?? '';
    if (boot.isNotEmpty) {
      unawaited(_applyBootstrapTargetDir(boot));
    } else {
      unawaited(_loadCachedTargetDir());
    }
  }

  Future<void> _applyBootstrapTargetDir(String dir) async {
    await setTargetDir(dir);
    if (targetDir.value.trim() != dir.trim()) {
      await _loadCachedTargetDir();
    }
  }

  Future<void> pickTargetDir(BuildContext context) async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: targetDir.value.trim().isEmpty ? null : targetDir.value,
    );
    if (res == null || res.isEmpty) return;
    final picked = res.first.trim();
    if (picked.isEmpty) return;
    checkingTargetDir.value = true;
    try {
      final status = await _checkServerDirAccess(picked);
      if (status == ServerDirAccessStatus.ok) {
        targetDir.value = picked;
        await CacheManager().setString(_targetDirCacheKey(), picked);
        return;
      }

      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'upload_center_target_cannot_upload'.tr,
        buttonText: 'ok'.tr,
        onPressed: () => pickTargetDir(context),
      );
    } finally {
      checkingTargetDir.value = false;
    }
  }

  Future<void> setTargetDir(String dir) async {
    final v = dir.trim();
    if (v.isEmpty) return;
    checkingTargetDir.value = true;
    try {
      final ok = await _validateServerDir(v);
      if (!ok) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      targetDir.value = v;
      await CacheManager().setString(_targetDirCacheKey(), v);
    } finally {
      checkingTargetDir.value = false;
    }
  }

  Future<void> clearTargetDir() async {
    targetDir.value = '';
    await CacheManager().remove(_targetDirCacheKey());
  }

  Future<void> setUploadLivePhotoVideo(bool enabled) async {
    uploadLivePhotoVideo.value = enabled;
    await CacheManager().setBool(uploadLivePhotoVideoCacheKey, enabled);
  }

  void _loadCachedOptions() {
    uploadLivePhotoVideo.value =
        CacheManager().getBool(uploadLivePhotoVideoCacheKey) ?? false;
  }

  Future<void> _loadCachedTargetDir() async {
    final cached = CacheManager().getString(_targetDirCacheKey())?.trim() ?? '';
    if (cached.isEmpty) return;
    checkingTargetDir.value = true;
    try {
      final status = await _checkServerDirAccess(cached);
      if (status != ServerDirAccessStatus.ok) {
        await CacheManager().remove(_targetDirCacheKey());
        return;
      }
      targetDir.value = cached;
    } finally {
      checkingTargetDir.value = false;
    }
  }

  Future<bool> _validateServerDir(String dir) async {
    return await _checkServerDirAccess(dir) == ServerDirAccessStatus.ok;
  }

  Future<ServerDirAccessStatus> _checkServerDirAccess(String dir) async {
    return FileApiService.instance.checkServerDirAccess(dir);
  }
}
