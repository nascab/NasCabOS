import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../utils/toast_util.dart';

class MobileMediaFilePicker {
  static Future<List<Map<String, dynamic>>> pickMediaUploadEntries(
    BuildContext context, {
    required bool includeLivePhotoVideo,
    int maxAssets = 500,
  }) async {
    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) return const <Map<String, dynamic>>[];
    if (!context.mounted) return const <Map<String, dynamic>>[];

    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        requestType: RequestType.common,
        maxAssets: maxAssets,
        limitedPermissionOverlayPredicate: (_) => false,
      ),
      permissionRequestOption: _buildPermissionRequestOption(
        requestType: RequestType.common,
      ),
    );
    if (assets == null || assets.isEmpty) return const <Map<String, dynamic>>[];

    final files = <Map<String, dynamic>>[];
    for (final e in assets) {
      final name = (await e.titleAsync).trim();
      final f = await e.originFile;
      if (f == null) continue;
      files.add({'file': XFile(f.path), 'name': name});

      if (!includeLivePhotoVideo) continue;
      final liveVideo = await e.originFileWithSubtype;
      if (liveVideo == null) continue;

      String? videoName;
      if (name.isNotEmpty) {
        final base = p.basenameWithoutExtension(name);
        if (base.isNotEmpty) {
          videoName = '$base.MOV';
        }
      }
      files.add({'file': XFile(liveVideo.path), 'name': videoName});
    }
    return files;
  }

  static Future<List<PlatformFile>> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
      withReadStream: false,
    );
    if (res == null || res.files.isEmpty) return const <PlatformFile>[];
    return res.files;
  }

  static Future<bool> _ensurePhotoPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: _buildPermissionRequestOption(
        requestType: RequestType.common,
      ),
    );
    if (state.hasAccess) return true;
    ToastUtil.show('photo_library_permission_missing'.tr);
    return false;
  }

  static PermissionRequestOption _buildPermissionRequestOption({
    required RequestType requestType,
  }) {
    if (Platform.isAndroid) {
      return PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: requestType,
          mediaLocation: true,
        ),
      );
    }
    return const PermissionRequestOption();
  }
}
