import 'dart:convert';
import 'dart:io';

import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../controllers/mobile_upload_center_controller.dart';
import '../../../controllers/upload_controller.dart';
import '../../../models/transfer_task.dart';
import '../../../utils/mobile_media_file_picker.dart';
import 'upload_center_task_card.dart';

class UploadCenterUploadingTab extends StatelessWidget {
  const UploadCenterUploadingTab({
    super.key,
    required this.uploadCtrl,
    required this.pageCtrl,
  });

  final UploadController uploadCtrl;
  final MobileUploadCenterController pageCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final list =
          uploadCtrl.tasks
              .where(
                (t) =>
                    t.type == TransferType.upload &&
                    t.status != TransferStatus.completed,
              )
              .toList()
            ..sort((a, b) {
              // 正在上传的排在最上面，其余按创建时间倒序
              final aOrder = a.status == TransferStatus.uploading ? 0 : 1;
              final bOrder = b.status == TransferStatus.uploading ? 0 : 1;
              final cmp = aOrder.compareTo(bOrder);
              if (cmp != 0) return cmp;
              return b.createdTime.compareTo(a.createdTime);
            });

      final bottomInset = MediaQuery.of(context).padding.bottom;
      final bottomBarHeight = 56.0 + bottomInset;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: _SettingsCard(uploadCtrl: uploadCtrl, pageCtrl: pageCtrl),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: list.isEmpty ? null : uploadCtrl.pauseAll,
                  child: Text('task_pause_all'.tr),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: list.isEmpty
                      ? null
                      : () {
                          final toDelete = uploadCtrl.tasks
                              .where(
                                (t) =>
                                    t.type == TransferType.upload &&
                                    t.status != TransferStatus.completed,
                              )
                              .toList();
                          for (final t in toDelete) {
                            uploadCtrl.deleteTask(t);
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text('task_clear_all'.tr),
                ),
                const Spacer(),
                Obx(() {
                  final target = pageCtrl.targetDir.value.trim();
                  final enabled = target.isNotEmpty && list.isNotEmpty;
                  return TextButton(
                    onPressed: enabled ? uploadCtrl.startAll : null,
                    child: Text('task_start_all'.tr),
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? CustomNoData(text: 'upload_center_empty'.tr)
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      bottomBarHeight + 8,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final task = list[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: UploadCenterTaskCard(
                          task: task,
                          uploadCtrl: uploadCtrl,
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _pickMedia(context),
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(16),
                            ),
                            child: SizedBox.expand(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Icon(
                                    Icons.photo_library_outlined,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'upload_center_pick_media'.tr,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: double.infinity,
                        color: theme.dividerColor,
                      ),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _pickFiles(context),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(16),
                            ),
                            child: SizedBox.expand(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Icon(
                                    Icons.upload_file,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'folder_upload_file'.tr,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  /// 上传照片/视频：统一使用相册选择器（wechat_assets_picker），
  /// 直接基于相册资源上传，避免 Android 上 FilePicker 先拷贝到缓存再上传。
  Future<void> _pickMedia(BuildContext context) async {
    final target = pageCtrl.targetDir.value.trim();
    if (target.isEmpty) {
      ToastUtil.show('quick_share_path_required'.tr);
      return;
    }
    final files = await MobileMediaFilePicker.pickMediaUploadEntries(
      context,
      includeLivePhotoVideo: pageCtrl.uploadLivePhotoVideo.value,
    );
    await _enqueueAndConfirm(files, target);
  }

  Future<void> _pickFiles(BuildContext context) async {
    final target = pageCtrl.targetDir.value.trim();
    if (target.isEmpty) {
      ToastUtil.show('quick_share_path_required'.tr);
      return;
    }

    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: false,
      withReadStream: false,
    );
    if (res == null) return;

    final files = <XFile>[];
    for (final f in res.files) {
      final pathStr = f.path?.trim() ?? '';
      if (pathStr.isEmpty) continue;
      files.add(XFile(pathStr, name: _pickPreferredUploadName(f)));
    }
    await _enqueueAndConfirm(files, target);
  }

  Future<void> _enqueueAndConfirm(List<dynamic> files, String target) async {
    if (files.isEmpty) return;
    final added = await uploadCtrl.enqueueXFiles(
      files,
      target,
      startImmediately: false,
    );
    if (added.isEmpty) return;

    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'upload_center_start_now_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    for (final t in added) {
      uploadCtrl.startTask(t);
    }
  }

  List<XFile> _expandPossibleLivePhotoPairs(List<XFile> input) {
    final seen = <String>{};
    final out = <XFile>[];

    for (final f in input) {
      final pathStr = f.path.trim();
      if (pathStr.isEmpty) continue;
      if (seen.add(pathStr)) out.add(f);
    }

    final imageExts = <String>{'jpg', 'jpeg', 'png', 'heic', 'heif'};
    final videoExts = <String>{'mov', 'mp4', 'm4v'};
    final pairVideoExts = <String>['mov', 'mp4', 'm4v'];
    final pairImageExts = <String>['heic', 'jpg', 'jpeg', 'png'];

    for (final f in List<XFile>.from(out)) {
      final pathStr = f.path.trim();
      final dot = pathStr.lastIndexOf('.');
      if (dot <= 0 || dot >= pathStr.length - 1) continue;

      final ext = pathStr.substring(dot + 1).toLowerCase();
      final base = pathStr.substring(0, dot);

      if (imageExts.contains(ext)) {
        for (final vExt in pairVideoExts) {
          final candidate = '$base.$vExt';
          if (!seen.contains(candidate) && File(candidate).existsSync()) {
            seen.add(candidate);
            out.add(XFile(candidate));
            break;
          }
        }
        continue;
      }

      if (videoExts.contains(ext)) {
        for (final iExt in pairImageExts) {
          final candidate = '$base.$iExt';
          if (!seen.contains(candidate) && File(candidate).existsSync()) {
            seen.add(candidate);
            out.add(XFile(candidate));
            break;
          }
        }
      }
    }

    return out;
  }

  String? _pickPreferredUploadName(PlatformFile f) {
    final n = f.name.trim();
    if (n.isNotEmpty && !_looksLikeGeneratedMediaName(n)) {
      return n;
    }

    final id = (f.identifier ?? '').trim();
    if (id.isNotEmpty) {
      final fromId = _extractNameFromIdentifier(id);
      if (fromId != null &&
          fromId.trim().isNotEmpty &&
          !_looksLikeGeneratedMediaName(fromId.trim())) {
        return fromId.trim();
      }

      final ext = _safeExt(n, f.extension);
      final digest = sha1.convert(utf8.encode(id)).toString().substring(0, 12);
      return ext.isEmpty ? 'media_$digest' : 'media_$digest.$ext';
    }

    if (n.isNotEmpty) return n;
    return null;
  }

  bool _looksLikeGeneratedMediaName(String name) {
    final lower = name.toLowerCase();
    if (!(lower.startsWith('image_') || lower.startsWith('video_'))) {
      return false;
    }
    final dot = lower.lastIndexOf('.');
    if (dot <= 0) return false;
    final base = lower.substring(0, dot);
    final parts = base.split('_');
    if (parts.length < 3) return false;
    final uuid = parts[1];
    final ts = parts[2];
    final uuidOk = RegExp(r'^[0-9a-f-]{36}$').hasMatch(uuid);
    final tsOk = RegExp(r'^\d{9,}$').hasMatch(ts);
    return uuidOk && tsOk;
  }

  String _safeExt(String name, String? ext) {
    final e = (ext ?? '').trim().toLowerCase();
    if (e.isNotEmpty) return e;
    final fromName = p
        .extension(name)
        .replaceFirst('.', '')
        .trim()
        .toLowerCase();
    return fromName;
  }

  String? _extractNameFromIdentifier(String identifier) {
    final uri = Uri.tryParse(identifier);
    if (uri != null) {
      if (uri.scheme == 'file') {
        final base = p.basename(uri.path);
        return base.isEmpty ? null : base;
      }
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        return last.isEmpty ? null : last;
      }
    }

    final idx = identifier.lastIndexOf('/');
    if (idx >= 0 && idx < identifier.length - 1) {
      final last = identifier.substring(idx + 1).trim();
      return last.isEmpty ? null : last;
    }
    return null;
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.uploadCtrl, required this.pageCtrl});

  final UploadController uploadCtrl;
  final MobileUploadCenterController pageCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: isLight ? 0.45 : 0.8),
          ),
          boxShadow: isLight
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => pageCtrl.pickTargetDir(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'encrypted_space_export_target_path'.tr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Obx(() {
                              final v = pageCtrl.targetDir.value.trim();
                              return Text(
                                v.isEmpty ? 'quick_share_path_hint'.tr : v,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final selected = await _showNameStrategyPicker(context);
                  if (selected != null) {
                    uploadCtrl.nameStrategy.value = selected;
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.rule_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'folder_name_strategy'.tr,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Obx(() {
                              final v = uploadCtrl.nameStrategy.value;
                              return Text(
                                v.tr,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.dividerColor),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: Obx(() {
                            final options = <String, String>{
                              '': 'upload_center_save_type_root',
                              'day': 'upload_center_save_type_day',
                              'month': 'upload_center_save_type_month',
                              'year': 'upload_center_save_type_year',
                            };
                            final v = uploadCtrl.saveType.value;
                            return DropdownButton<String>(
                              isExpanded: true,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              value: options.containsKey(v) ? v : '',
                              items: options.entries
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.value.tr),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (next) {
                                if (next == null) return;
                                uploadCtrl.setSaveType(next);
                              },
                            );
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CustomBorderedIconButton(
                      tooltip: 'tip'.tr,
                      size: 28,
                      iconSize: 18,
                      onTap: () {
                        DialogUtil.showInfoDialog(
                          title: 'tip'.tr,
                          content: 'upload_center_save_type_tip'.tr,
                        );
                      },
                      icon: Icons.help_outline,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (Platform.isIOS) ...[
                Divider(height: 1, color: theme.dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.motion_photos_on_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'upload_center_livephoto_video'.tr,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Obx(() {
                        return Switch(
                          value: pageCtrl.uploadLivePhotoVideo.value,
                          onChanged: pageCtrl.setUploadLivePhotoVideo,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showNameStrategyPicker(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('skip'.tr),
                onTap: () => Navigator.pop(ctx, 'skip'),
              ),
              ListTile(
                title: Text('overwrite'.tr),
                onTap: () => Navigator.pop(ctx, 'overwrite'),
              ),
              ListTile(
                title: Text('rename'.tr),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}
