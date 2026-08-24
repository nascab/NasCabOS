import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/api/dio_bad_certificate_compat.dart';
import '../../../core/api/api_error_localizer.dart';
import '../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../core/api/p2p_rtc_web.dart';
import '../../../core/routes/app_routes.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../base/components/custom_text_field.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../gallery/controllers/custom_gallery_controller.dart';
import '../../gallery/views/custom_gallery.dart';
import '../../home/views/pc_home_controller.dart';
import '../../transfer/controllers/download_controller.dart';
import '../../transfer/controllers/upload_parts/upload_web_file_helper.dart';
import '../../transfer/utils/mobile_media_file_picker.dart';
import 'encrypted_space_drop_helper.dart';
import '../service/encrypted_space_api_service.dart';
import '../../base/components/mobile_upload_source_picker.dart';
import '../../base/components/custom_bordered_icon_button.dart';

class EncryptedSpaceController extends GetxController {
  final _api = EncryptedSpaceApiService();

  final RxList<Map<String, dynamic>> spaces = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final Rxn<EncryptedSpaceActiveSpace> activeSpace =
      Rxn<EncryptedSpaceActiveSpace>();
  final RxList<Map<String, dynamic>> exportTasks = <Map<String, dynamic>>[].obs;
  final RxBool exportTasksLoading = false.obs;
  final RxString exportTasksErrorText = ''.obs;
  Timer? _exportTaskDialogTimer;

  @override
  void onInit() {
    super.onInit();
    refreshList(showLoading: false);
  }

  @override
  void onClose() {
    final closingSpaceId = activeSpace.value?.spaceId ?? 0;
    if (closingSpaceId > 0) {
      _deleteTokenSilently(spaceId: closingSpaceId);
    }
    _exportTaskDialogTimer?.cancel();
    _exportTaskDialogTimer = null;
    super.onClose();
  }

  Future<void> refreshList({bool showLoading = true}) async {
    isLoading.value = true;
    errorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list();
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        spaces.assignAll(const []);
        return;
      }
      final raw = res.data ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      spaces.assignAll(list);
      final currentActiveId = activeSpace.value?.spaceId;
      if (currentActiveId != null &&
          !list.any(
            (e) => int.tryParse('${e['id'] ?? ''}') == currentActiveId,
          )) {
        activeSpace.value = null;
      }
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      spaces.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
    }
  }

  Future<void> refreshExportTasks({bool showLoading = false}) async {
    exportTasksLoading.value = true;
    exportTasksErrorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.exportTaskList();
      if (!res.success) {
        exportTasksErrorText.value = res.message ?? 'operation_failed'.tr;
        exportTasks.assignAll(const []);
        return;
      }
      final raw = res.data ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      exportTasks.assignAll(list);
    } catch (_) {
      exportTasksErrorText.value = 'operation_failed'.tr;
      exportTasks.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      exportTasksLoading.value = false;
    }
  }

  void openActiveSpace(EncryptedSpaceActiveSpace space) {
    activeSpace.value = space;
  }

  void closeActiveSpace() {
    final closingSpaceId = activeSpace.value?.spaceId ?? 0;
    activeSpace.value = null;
    if (closingSpaceId > 0) {
      _deleteTokenSilently(spaceId: closingSpaceId);
    }
  }

  Future<void> _deleteTokenSilently({required int spaceId}) async {
    try {
      await _api.deleteToken(spaceId: spaceId);
    } catch (_) {}
  }

  String exportTaskStatusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'pending') return 'waiting'.tr;
    if (s == 'running') return 'processing'.tr;
    if (s == 'success') return 'completed'.tr;
    if (s == 'error') return 'failed'.tr;
    return raw.trim().isEmpty ? '-' : raw.trim();
  }

  Future<void> showExportTasksDialog(BuildContext context) async {
    final theme = Theme.of(context);
    _exportTaskDialogTimer?.cancel();
    _exportTaskDialogTimer = null;

    await refreshExportTasks(showLoading: false);

    _exportTaskDialogTimer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => refreshExportTasks(showLoading: false),
    );

    try {
      await Get.dialog(
        Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'encrypted_space_export_tasks'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CustomBorderedIconButton(
                        icon: Icons.refresh,
                        tooltip: 'refresh'.tr,
                        onTap: () =>
                            refreshExportTasks(showLoading: false),
                      ),
                      const SizedBox(width: 8),
                      CustomBorderedIconButton(
                        icon: Icons.cleaning_services_outlined,
                        tooltip: 'delete'.tr,
                        onTap: () => clearFinishedExportTasksFlow(),
                      ),
                      const SizedBox(width: 8),
                      CustomBorderedIconButton(
                        icon: Icons.close,
                        tooltip: 'close'.tr,
                        onTap: () => Get.back(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Obx(() {
                      if (exportTasksLoading.value && exportTasks.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (exportTasksErrorText.value.isNotEmpty) {
                        return Center(child: Text(exportTasksErrorText.value));
                      }
                      if (exportTasks.isEmpty) {
                        return Center(child: Text('no_data'.tr));
                      }
                      return ListView.separated(
                        itemCount: exportTasks.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final it = exportTasks[i];
                          final id = int.tryParse('${it['id'] ?? ''}') ?? 0;
                          final spaceId =
                              int.tryParse('${it['space_id'] ?? ''}') ?? 0;
                          final target = (it['target_path'] ?? '')
                              .toString()
                              .trim();
                          final status = exportTaskStatusLabel(
                            '${it['status'] ?? ''}',
                          );
                          final progress = (it['progress'] ?? '')
                              .toString()
                              .trim();
                          final doneFiles =
                              int.tryParse('${it['done_files'] ?? ''}') ?? 0;
                          final totalFiles =
                              int.tryParse('${it['total_files'] ?? ''}') ?? 0;
                          final lastError = (it['last_error'] ?? '')
                              .toString()
                              .trim();
                          final countText = (totalFiles > 0)
                              ? '$doneFiles/$totalFiles'
                              : (doneFiles > 0 ? '$doneFiles' : '');

                          final subtitleParts = <String>[
                            if (progress.isNotEmpty) progress,
                            if (countText.isNotEmpty) countText,
                            status,
                          ];
                          final subtitle = subtitleParts.join(' · ');

                          return ListTile(
                            dense: true,
                            title: Text(
                              '#$id · ${'encrypted_space_space_id'.tr}: $spaceId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (target.isNotEmpty)
                                  Text(
                                    '${'encrypted_space_export_target_path'.tr}: $target',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (lastError.isNotEmpty)
                                  Text(
                                    '${'error'.tr}: $lastError',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'delete'.tr,
                              onPressed: id > 0
                                  ? () => deleteExportTaskFlow(id: id)
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );
    } finally {
      _exportTaskDialogTimer?.cancel();
      _exportTaskDialogTimer = null;
    }
  }

  Future<void> deleteExportTaskFlow({required int id}) async {
    if (id <= 0) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: "${'confirm_delete'.tr} #$id",
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.deleteExportTask(id: id);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      await refreshExportTasks(showLoading: false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> clearFinishedExportTasksFlow() async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'encrypted_space_export_clear_finished_confirm'.tr,
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.clearFinishedExportTasks();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      await refreshExportTasks(showLoading: false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> exportSpaceFlow(
    BuildContext context,
    Map<String, dynamic> space,
  ) async {
    final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
    if (id <= 0) return;

    await Get.dialog<void>(
      Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: _EncryptedExportDialogContent(
          pickerContext: context,
          onSubmit: (pwd, targetPath) async {
            DialogUtil.showLoading(message: 'loading'.tr);
            try {
              final res = await _api.addExportTask(
                spaceId: id,
                spacePwd: pwd,
                targetPath: targetPath,
              );
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
                return;
              }
              ToastUtil.show('operation_success'.tr);
              await refreshExportTasks(showLoading: false);
              if (Get.isDialogOpen == true) Get.back();
            } finally {
              DialogUtil.dismissLoading(force: true);
            }
          },
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> createSpaceFlow(BuildContext context) async {
    await Get.dialog<void>(
      Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: _EncryptedCreateSpaceDialogContent(
          pickerContext: context,
          onSubmit: (name, pwd, folderPath) async {
            DialogUtil.showLoading(message: 'loading'.tr);
            try {
              final res = await _api.addSpace(
                folderPath: folderPath.trim(),
                spaceName: name,
                spacePwd: pwd,
              );
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
                return;
              }
              ToastUtil.show('operation_success'.tr);
              await refreshList(showLoading: false);
              if (Get.isDialogOpen == true) Get.back();
            } finally {
              DialogUtil.dismissLoading(force: true);
            }
          },
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> importSpaceFlow(BuildContext context) async {
    await Get.dialog<void>(
      Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: _EncryptedImportSpaceDialogContent(
          pickerContext: context,
          onSubmit: (name, pwd, folderPath) async {
            DialogUtil.showLoading(message: 'loading'.tr);
            try {
              final res = await _api.importSpace(
                folderPath: folderPath.trim(),
                spaceName: name,
                spacePwd: pwd,
              );
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
                return;
              }
              ToastUtil.show('operation_success'.tr);
              await refreshList(showLoading: false);
              if (Get.isDialogOpen == true) Get.back();
            } finally {
              DialogUtil.dismissLoading(force: true);
            }
          },
        ),
      ),
      barrierDismissible: false,
    );
  }

  void openSpaceFlow(
    BuildContext context,
    Map<String, dynamic> space, {
    void Function(Map<String, dynamic> data)? onSuccess,
  }) {
    final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    DialogUtil.showPasswordInputDialog(
      title: 'password'.tr,
      message: 'input_please'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
      onConfirm: (pwd) async {
        final p = pwd.trim();
        if (p.isEmpty) return;
        DialogUtil.showLoading(message: 'loading'.tr);
        try {
          final res = await _api.checkPwd(spaceId: id, spacePwd: p);
          if (!res.success) {
            ToastUtil.show(res.message ?? 'operation_failed'.tr);
            return;
          }
          ToastUtil.show('operation_success'.tr);
          final data = res.data;
          if (data != null) {
            onSuccess?.call(data);
          }
        } finally {
          DialogUtil.dismissLoading(force: true);
        }
      },
    );
  }

  Future<void> renameSpaceFlow(Map<String, dynamic> space) async {
    final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    final currentName = (space['space_name'] ?? '').toString().trim();
    final name = await DialogUtil.showInputDialog(
      title: 'rename'.tr,
      content: 'input_please'.tr,
      initialValue: currentName,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
      validator: (v) {
        final t = (v ?? '').trim();
        if (t.isEmpty) return 'name_cannot_be_empty'.tr;
        if (t.length > 30) return 'operation_failed'.tr;
        return null;
      },
    );
    final next = (name ?? '').trim();
    if (next.isEmpty) return;
    if (next == currentName) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.updateSpaceName(spaceId: id, spaceName: next);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      await refreshList(showLoading: false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> deleteSpaceFlow(Map<String, dynamic> space) async {
    final id = int.tryParse('${space['id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    final name = (space['space_name'] ?? '').toString().trim();
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: "${'confirm_delete'.tr}[${name.isEmpty ? id : name}]",
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.deleteSpace(spaceId: id);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'delete_failed'.tr);
        return;
      }
      ToastUtil.show('delete_success'.tr);
      if (activeSpace.value?.spaceId == id) {
        activeSpace.value = null;
      }
      await refreshList(showLoading: false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }
}

class _EncryptedExportDialogContent extends StatefulWidget {
  const _EncryptedExportDialogContent({
    required this.pickerContext,
    required this.onSubmit,
  });

  final BuildContext pickerContext;
  final Future<void> Function(String pwd, String targetPath) onSubmit;

  @override
  State<_EncryptedExportDialogContent> createState() =>
      _EncryptedExportDialogContentState();
}

class _EncryptedExportDialogContentState
    extends State<_EncryptedExportDialogContent> {
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _targetCtrl;
  String _targetPath = '';

  @override
  void initState() {
    super.initState();
    _pwdCtrl = TextEditingController();
    _targetCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'encrypted_space_export_title'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'close'.tr,
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'encrypted_space_export_space_pwd'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'encrypted_space_export_target_hint'.tr,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: _targetCtrl,
              labelText: 'encrypted_space_export_target_path'.tr,
              hintText: 'encrypted_space_export_pick_folder'.tr,
              readOnly: true,
              onTap: () async {
                final picked = await showFolderPickerBottomSheet(
                  widget.pickerContext,
                  multiSelect: false,
                  allowFileSelect: false,
                );
                final p = picked != null && picked.isNotEmpty
                    ? picked.first
                    : '';
                setState(() {
                  _targetPath = p;
                  _targetCtrl.text = p;
                });
              },
              suffixIcon: const Icon(Icons.folder_outlined),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  final pwd = _pwdCtrl.text.trim();
                  final target = _targetPath.trim();
                  if (pwd.isEmpty || target.isEmpty) {
                    ToastUtil.show('input_please'.tr);
                    return;
                  }
                  await widget.onSubmit(pwd, target);
                },
                child: Text('encrypted_space_export_start'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptedCreateSpaceDialogContent extends StatefulWidget {
  const _EncryptedCreateSpaceDialogContent({
    required this.pickerContext,
    required this.onSubmit,
  });

  final BuildContext pickerContext;
  final Future<void> Function(String name, String pwd, String folderPath)
  onSubmit;

  @override
  State<_EncryptedCreateSpaceDialogContent> createState() =>
      _EncryptedCreateSpaceDialogContentState();
}

class _EncryptedCreateSpaceDialogContentState
    extends State<_EncryptedCreateSpaceDialogContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _folderCtrl;
  String _folderPath = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _pwdCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '添加加密空间',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'close'.tr,
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: '空间名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '空间密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '选择加密空间数据保存位置(所选文件夹必须为空)',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: _folderCtrl,
              labelText: '空间路径',
              hintText: '选择文件夹',
              readOnly: true,
              onTap: () async {
                final picked = await showFolderPickerBottomSheet(
                  widget.pickerContext,
                  multiSelect: false,
                  allowFileSelect: false,
                );
                final p = picked != null && picked.isNotEmpty
                    ? picked.first
                    : '';
                setState(() {
                  _folderPath = p;
                  _folderCtrl.text = p;
                });
              },
              suffixIcon: const Icon(Icons.folder_outlined),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  final name = _nameCtrl.text.trim();
                  final pwd = _pwdCtrl.text.trim();
                  if (name.isEmpty || pwd.isEmpty || _folderPath.trim().isEmpty) {
                    ToastUtil.show('input_please'.tr);
                    return;
                  }
                  await widget.onSubmit(name, pwd, _folderPath.trim());
                },
                child: const Text('创建加密空间'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptedImportSpaceDialogContent extends StatefulWidget {
  const _EncryptedImportSpaceDialogContent({
    required this.pickerContext,
    required this.onSubmit,
  });

  final BuildContext pickerContext;
  final Future<void> Function(String name, String pwd, String folderPath)
  onSubmit;

  @override
  State<_EncryptedImportSpaceDialogContent> createState() =>
      _EncryptedImportSpaceDialogContentState();
}

class _EncryptedImportSpaceDialogContentState
    extends State<_EncryptedImportSpaceDialogContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _folderCtrl;
  String _folderPath = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _pwdCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '导入加密空间',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'close'.tr,
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: '空间名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '空间密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Text('选择要导入的加密空间目录', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            CustomTextField(
              controller: _folderCtrl,
              labelText: '空间路径',
              hintText: '选择文件夹',
              readOnly: true,
              onTap: () async {
                final picked = await showFolderPickerBottomSheet(
                  widget.pickerContext,
                  multiSelect: false,
                  allowFileSelect: false,
                );
                final p = picked != null && picked.isNotEmpty
                    ? picked.first
                    : '';
                setState(() {
                  _folderPath = p;
                  _folderCtrl.text = p;
                });
              },
              suffixIcon: const Icon(Icons.folder_outlined),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () async {
                  final name = _nameCtrl.text.trim();
                  final pwd = _pwdCtrl.text.trim();
                  if (name.isEmpty || pwd.isEmpty || _folderPath.trim().isEmpty) {
                    ToastUtil.show('input_please'.tr);
                    return;
                  }
                  await widget.onSubmit(name, pwd, _folderPath.trim());
                },
                child: const Text('导入加密空间'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EncryptedSpaceActiveSpace {
  final int spaceId;
  final String token;
  final String name;
  final String path;

  const EncryptedSpaceActiveSpace({
    required this.spaceId,
    required this.token,
    required this.name,
    required this.path,
  });
}

class EncryptedSpaceDetailController extends GetxController {
  EncryptedSpaceDetailController({required this.spaceId, required this.token});

  final int spaceId;
  final String token;

  final _api = EncryptedSpaceApiService();
  late final dio.Dio _dio;

  static const int _fileListPageSize = 200;

  static const String _prefsSortFieldKey =
      'encrypted_space_file_list_sort_field';
  static const String _prefsSortOrderKey =
      'encrypted_space_file_list_sort_order';

  static const Set<String> _allowedSortFields = {
    'id',
    'create_time',
    'check_time',
    'original_time',
    'size',
    'duration',
    'show_name',
  };

  final RxList<Map<String, dynamic>> files = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;

  /// 排序字段：id, create_time, check_time, original_time, size, duration, show_name
  final RxString sortField = 'original_time'.obs;
  final RxString sortOrder = 'desc'.obs;

  /// 与后端 private_space_index.file_type 一致：all / image / video / other
  final RxString fileTypeFilter = 'all'.obs;
  final RxString searchKeyword = ''.obs;
  final RxBool isUploading = false.obs;
  final RxString uploadingFileName = ''.obs;
  final RxInt uploadingIndex = 0.obs;
  final RxInt uploadingTotal = 0.obs;
  final RxDouble uploadingProgress = 0.0.obs;
  dio.CancelToken? _uploadCancelToken;

  final selectedIds = <int>{}.obs;
  final selectionRect = Rxn<Rect>();
  final selectionRectContent = Rxn<Rect>();
  Offset? _dragStartViewport;
  double _dragStartScrollOffset = 0;
  Set<int>? _dragSelectionBaseline;
  Timer? _searchDebounce;

  int? _lastTappedId;
  DateTime? _lastTapAt;

  @override
  void onClose() {
    _searchDebounce?.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    _dio = createDioWithBadCertificateCompat(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    _bootstrapList();
  }

  Future<void> _bootstrapList() async {
    await _loadSortFromPrefs();
    await refreshList(showLoading: false);
  }

  Future<void> _loadSortFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final f = prefs.getString(_prefsSortFieldKey)?.trim() ?? '';
      final o = prefs.getString(_prefsSortOrderKey)?.trim().toLowerCase();
      if (f.isNotEmpty && _allowedSortFields.contains(f)) {
        sortField.value = f;
      }
      if (o == 'asc') {
        sortOrder.value = 'asc';
      } else if (o == 'desc') {
        sortOrder.value = 'desc';
      }
    } catch (_) {}
  }

  Future<void> _saveSortToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSortFieldKey, sortField.value);
      await prefs.setString(_prefsSortOrderKey, sortOrder.value);
    } catch (_) {}
  }

  String _sanitizeDroppedName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    return s.replaceAll(RegExp(r'[\\/]+'), '__');
  }

  String fileTypeOf(Map<String, dynamic> item) {
    final t = item['file_type']?.toString().trim().toLowerCase();
    return (t == 'image' || t == 'video') ? t! : 'other';
  }

  int indexIdOf(Map<String, dynamic> item) {
    final raw = item['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  bool get isAdditiveSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasShift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
    final hasMeta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.meta);
    final hasCtrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.control);
    return hasShift || hasMeta || hasCtrl;
  }

  void toggleSelect(int id) {
    if (id <= 0) return;
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    selectedIds.refresh();
  }

  void clearSelect() {
    selectedIds.clear();
    selectedIds.refresh();
  }

  void selectOnly(int id) {
    if (id <= 0) return;
    selectedIds
      ..clear()
      ..add(id);
    selectedIds.refresh();
  }

  List<Map<String, dynamic>> getSelectedItems() {
    if (selectedIds.isEmpty) return const [];
    final next = <Map<String, dynamic>>[];
    for (final it in files) {
      final id = indexIdOf(it);
      if (id > 0 && selectedIds.contains(id)) next.add(it);
    }
    return next;
  }

  bool registerTap(int id) {
    final now = DateTime.now();
    final isDouble =
        _lastTappedId == id &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds <= 500;
    _lastTappedId = id;
    _lastTapAt = now;
    return isDouble;
  }

  void startDragSelection(Offset start, {double scrollOffset = 0}) {
    _dragStartViewport = start;
    _dragStartScrollOffset = scrollOffset;
    _dragSelectionBaseline = selectedIds.toSet();
    selectionRect.value = Rect.fromLTWH(start.dx, start.dy, 0, 0);
    selectionRectContent.value = Rect.fromLTWH(
      start.dx,
      start.dy + scrollOffset,
      0,
      0,
    );
  }

  void updateDragSelection(Offset current, {double scrollOffset = 0}) {
    final s = _dragStartViewport;
    if (s == null) return;
    final left = s.dx < current.dx ? s.dx : current.dx;
    final top = s.dy < current.dy ? s.dy : current.dy;
    final width = (s.dx - current.dx).abs();
    final height = (s.dy - current.dy).abs();
    selectionRect.value = Rect.fromLTWH(left, top, width, height);

    final startContentY = s.dy + _dragStartScrollOffset;
    final currentContentY = current.dy + scrollOffset;
    final topContent = startContentY < currentContentY
        ? startContentY
        : currentContentY;
    final heightContent = (startContentY - currentContentY).abs();
    selectionRectContent.value = Rect.fromLTWH(
      left,
      topContent,
      width,
      heightContent,
    );
  }

  void updateDragPreview(Set<int> hitIndexes) {
    final baseline = _dragSelectionBaseline ?? selectedIds.toSet();
    final additive = isAdditiveSelectionActive;
    if (!additive) {
      final next = <int>{};
      for (final i in hitIndexes) {
        if (i < 0 || i >= files.length) continue;
        final id = indexIdOf(files[i]);
        if (id > 0) next.add(id);
      }
      selectedIds
        ..clear()
        ..addAll(next);
      selectedIds.refresh();
    } else {
      final next = baseline.toSet();
      for (final i in hitIndexes) {
        if (i < 0 || i >= files.length) continue;
        final id = indexIdOf(files[i]);
        if (id <= 0) continue;
        if (baseline.contains(id)) {
          next.remove(id);
        } else {
          next.add(id);
        }
      }
      selectedIds
        ..clear()
        ..addAll(next);
      selectedIds.refresh();
    }
  }

  void finishDragSelection() {
    selectionRect.value = null;
    selectionRectContent.value = null;
    _dragStartViewport = null;
    _dragStartScrollOffset = 0;
    _dragSelectionBaseline = null;
  }

  String displayNameOf(Map<String, dynamic> item) {
    final showName = item['show_name']?.toString().trim() ?? '';
    if (showName.isNotEmpty) return showName;
    final b64 = item['filename']?.toString().trim() ?? '';
    if (b64.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(b64));
    } catch (_) {
      return b64;
    }
  }

  String buildDecodeUrl({
    required int indexId,
    String? type,
    bool download = false,
    String? fileName,
  }) {
    final baseUrl = ApiController.instance.baseUrl;
    final accessToken = ApiController.instance.accessToken?.trim() ?? '';

    final query = <String, String>{
      'spaceId': spaceId.toString(),
      'indexId': indexId.toString(),
      'spaceToken': token,
    };
    if (type != null && type.trim().isNotEmpty) query['type'] = type.trim();
    if (download) query['download'] = '1';
    if (download && fileName != null && fileName.trim().isNotEmpty) {
      query['fileName'] = fileName.trim();
    }
    if (accessToken.isNotEmpty) query['accessToken'] = accessToken;

    return Uri.parse(
      '$baseUrl/api/encryptedSpace/getDecodeFile',
    ).replace(queryParameters: query).toString();
  }

  void setSort({required String field, required String order}) {
    sortField.value = field;
    sortOrder.value = order;
    _saveSortToPrefs();
    refreshList(showLoading: false);
  }

  void setFileTypeFilter(String raw) {
    final v = raw.trim().toLowerCase();
    const allowed = {'all', 'image', 'video', 'other'};
    if (!allowed.contains(v)) return;
    if (fileTypeFilter.value == v) return;
    fileTypeFilter.value = v;
    refreshList(showLoading: false);
  }

  void onSearchChanged(String value) {
    searchKeyword.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      refreshList(showLoading: false);
    });
  }

  void clearSearch() {
    searchKeyword.value = '';
    refreshList(showLoading: false);
  }

  Future<void> refreshList({bool showLoading = true}) async {
    isLoading.value = true;
    errorText.value = '';
    hasMore.value = true;
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.getFileList(
        spaceId: spaceId,
        token: token,
        count: _fileListPageSize,
        offsetCount: 0,
        orderField: sortField.value,
        orderType: sortOrder.value,
        fileType: fileTypeFilter.value,
        keyword: searchKeyword.value,
      );
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        files.assignAll(const []);
        return;
      }
      final raw = res.data ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      files.assignAll(list);
      hasMore.value = list.length >= _fileListPageSize;
      if (selectedIds.isNotEmpty) {
        final validIds = list.map(indexIdOf).where((e) => e > 0).toSet();
        selectedIds.removeWhere((id) => !validIds.contains(id));
        selectedIds.refresh();
      }
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      files.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
    }
  }

  /// 滚动到底部时加载下一页
  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore.value || isLoading.value) return;
    loadingMore.value = true;
    try {
      final res = await _api.getFileList(
        spaceId: spaceId,
        token: token,
        count: _fileListPageSize,
        offsetCount: files.length,
        orderField: sortField.value,
        orderType: sortOrder.value,
        fileType: fileTypeFilter.value,
        keyword: searchKeyword.value,
      );
      if (!res.success) return;
      final raw = res.data ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      files.addAll(list);
      hasMore.value = list.length >= _fileListPageSize;
    } catch (_) {
      hasMore.value = false;
    } finally {
      loadingMore.value = false;
    }
  }

  Future<void> deleteItemsFlow(List<Map<String, dynamic>> items) async {
    final ids = items.map(indexIdOf).where((id) => id > 0).toList();
    if (ids.isEmpty) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: "${'confirm_delete'.tr} (${ids.length})",
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.deleteSpaceFiles(spaceId: spaceId, ids: ids);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'delete_failed'.tr);
        return;
      }
      clearSelect();
      ToastUtil.show('delete_success'.tr);
      await refreshList(showLoading: false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  int _encryptedGalleryIndexIdOf(Map<String, dynamic> item) {
    final raw = item['_encryptedSpaceIndexId'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw != null) return int.tryParse(raw.toString()) ?? 0;
    return indexIdOf(item);
  }

  String _encryptedGalleryNameOf(Map<String, dynamic> item) {
    final name = (item['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return displayNameOf(item);
  }

  Future<bool> deleteItemFromGalleryFlow(Map<String, dynamic> item) async {
    final id = _encryptedGalleryIndexIdOf(item);
    if (id <= 0) return false;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: "${'confirm_delete'.tr} (1)",
      confirmText: 'delete'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return false;

    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final res = await _api.deleteSpaceFiles(spaceId: spaceId, ids: [id]);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'delete_failed'.tr);
        return false;
      }
      ToastUtil.show('delete_success'.tr);
      await refreshList(showLoading: false);
      return true;
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> downloadItemFromGallery(Map<String, dynamic> item) async {
    final id = _encryptedGalleryIndexIdOf(item);
    if (id <= 0) return;
    final name = _encryptedGalleryNameOf(item);
    final urlRaw = (item['downloadUrl'] ?? '').toString().trim();
    final url = urlRaw.isNotEmpty
        ? urlRaw
        : buildDecodeUrl(indexId: id, download: true, fileName: name);
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload([url]);
  }

  Future<void> uploadFilesFlow([BuildContext? anchorContext]) async {
    try {
      if (kIsWeb) {
        final picked = await UploadWebFileHelper.pickFiles();
        if (picked.isEmpty) return;
        final entries = picked
            .map((f) {
              final name = UploadWebFileHelper.getFileName(f).trim();
              return name.isEmpty
                  ? null
                  : _EncryptedSpaceUploadEntry.webFile(fileName: name, file: f);
            })
            .whereType<_EncryptedSpaceUploadEntry>()
            .toList(growable: false);
        if (entries.isEmpty) return;
        await _uploadEntries(entries);
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final context = anchorContext ?? Get.context;
        if (context == null) return;
        final source = await showMobileUploadSourcePicker(context);
        if (source == null) return;

        if (source == MobileUploadSourceType.media) {
          final picked = await MobileMediaFilePicker.pickMediaUploadEntries(
            context,
            includeLivePhotoVideo: false,
          );
          final entries = picked
              .map((it) {
                final file = it['file'];
                if (file is! XFile) return null;
                final path = file.path.trim();
                if (path.isEmpty) return null;
                final name = (it['name'] ?? '').toString().trim();
                return _EncryptedSpaceUploadEntry.path(
                  fileName: name.isEmpty ? file.name : name,
                  filePath: path,
                );
              })
              .whereType<_EncryptedSpaceUploadEntry>()
              .toList(growable: false);
          if (entries.isEmpty) return;
          await _uploadEntries(entries);
          return;
        }

        final pickedFiles = await MobileMediaFilePicker.pickFiles();
        final valid = pickedFiles.where((f) => (f.path ?? '').trim().isNotEmpty);
        if (valid.isEmpty) return;
        final entries = valid
            .map(
              (f) => _EncryptedSpaceUploadEntry.path(
                fileName: f.name,
                filePath: (f.path ?? '').trim(),
              ),
            )
            .toList(growable: false);
        await _uploadEntries(entries);
        return;
      }

      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: false,
        type: FileType.any,
      );
      final picked = res?.files ?? const <PlatformFile>[];
      final valid = picked.where((f) => (f.path ?? '').trim().isNotEmpty);
      if (valid.isEmpty) return;
      final entries = valid
          .map(
            (f) => _EncryptedSpaceUploadEntry.path(
              fileName: f.name,
              filePath: (f.path ?? '').trim(),
            ),
          )
          .toList(growable: false);
      await _uploadEntries(entries);
    } catch (e) {
      ToastUtil.show(_serverMessage(e));
    }
  }

  Future<void> uploadDroppedFiles(List<XFile> dropped) async {
    if (dropped.isEmpty) return;
    if (isUploading.value) return;

    final out = <_EncryptedSpaceUploadEntry>[];
    for (final f in dropped) {
      final path = f.path;
      if (path.trim().isEmpty) continue;
      if (await EncryptedSpaceDropHelper.isDirectory(path)) {
        final rootName = p.basename(path);
        await for (final filePath
            in EncryptedSpaceDropHelper.listFilesRecursively(path)) {
          final rel = p.relative(filePath, from: path);
          final fullRel = rel.isEmpty ? rootName : p.join(rootName, rel);
          final name = _sanitizeDroppedName(fullRel);
          if (name.isEmpty) continue;
          out.add(
            _EncryptedSpaceUploadEntry.path(fileName: name, filePath: filePath),
          );
        }
      } else {
        final name = (f.name).trim();
        if (name.isEmpty) continue;
        out.add(
          _EncryptedSpaceUploadEntry.path(fileName: name, filePath: path),
        );
      }
    }
    if (out.isEmpty) return;
    await _uploadEntries(out);
  }

  Future<void> uploadDroppedWebDataTransfer(dynamic transfer) async {
    if (isUploading.value) return;
    final items = await UploadWebFileHelper.getFilesFromDataTransfer(transfer);
    if (items.isEmpty) return;

    final out = <_EncryptedSpaceUploadEntry>[];
    for (final it in items) {
      final file = it['file'];
      if (file == null) continue;
      final rawPath = (it['path'] ?? '').toString().trim();
      final fallback = UploadWebFileHelper.getFileName(file);
      final name = _sanitizeDroppedName(
        rawPath.isNotEmpty ? rawPath : fallback,
      );
      if (name.isEmpty) continue;
      out.add(_EncryptedSpaceUploadEntry.webFile(fileName: name, file: file));
    }
    if (out.isEmpty) return;
    await _uploadEntries(out);
  }

  Future<void> cancelUploadFlow() async {
    if (!isUploading.value) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: '确认取消上传？',
      confirmText: 'confirm'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    _uploadCancelToken?.cancel('user_cancel');
  }

  Future<void> _uploadEntries(List<_EncryptedSpaceUploadEntry> entries) async {
    if (entries.isEmpty) return;
    if (isUploading.value) return;

    isUploading.value = true;
    uploadingTotal.value = entries.length;
    uploadingIndex.value = 0;
    uploadingProgress.value = 0.0;
    uploadingFileName.value = '';
    _uploadCancelToken = dio.CancelToken();

    try {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        uploadingIndex.value = i + 1;
        uploadingFileName.value = e.fileName;
        uploadingProgress.value = 0.0;

        if (e.webFile != null) {
          final accessToken = ApiController.instance.accessToken?.trim() ?? '';
          final size = UploadWebFileHelper.getFileSize(e.webFile);
          if (size <= 0) throw Exception('operation_failed'.tr);

          const maxChunkSize = 5 * 1024 * 1024;
          final chunkSize = size < maxChunkSize ? size : maxChunkSize;
          final totalChunks = (size + chunkSize - 1) ~/ chunkSize;
          final sessionHash = '${Uuid().v4()}_$chunkSize';
          final mtimeMs = UploadWebFileHelper.getLastModified(e.webFile);
          final url = _buildChunkUploadUrl();

          for (var part = 0; part < totalChunks; part++) {
            final start = part * chunkSize;
            final end = (start + chunkSize) > size ? size : (start + chunkSize);
            await UploadWebFileHelper.uploadChunk(
              e.webFile,
              url,
              accessToken,
              sessionHash,
              '',
              chunkSize,
              e.fileName,
              totalChunks,
              part,
              start,
              end,
              _uploadCancelToken,
              'skip',
              null,
              fileMtimeMs: mtimeMs,
              onProgress: (sent, total) {
                final overall = start + sent;
                uploadingProgress.value = (overall / size).clamp(0.0, 1.0);
              },
            );
            uploadingProgress.value = (end / size).clamp(0.0, 1.0);
          }
        } else if (e.filePath != null) {
          await _uploadPath(
            filePath: e.filePath!,
            fileName: e.fileName,
            cancelToken: _uploadCancelToken,
            onSendProgress: (sent, total) {
              if (total <= 0) return;
              uploadingProgress.value = sent / total;
            },
          );
        }
      }
      await refreshList(showLoading: false);
    } catch (e) {
      if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
        ToastUtil.show('cancel'.tr);
      } else {
        ToastUtil.show(_serverMessage(e));
      }
    } finally {
      isUploading.value = false;
      uploadingFileName.value = '';
      uploadingIndex.value = 0;
      uploadingTotal.value = 0;
      uploadingProgress.value = 0.0;
      _uploadCancelToken = null;
    }
  }

  Future<void> _uploadPath({
    required String filePath,
    required String fileName,
    dio.CancelToken? cancelToken,
    dio.ProgressCallback? onSendProgress,
  }) async {
    final url = _buildChunkUploadUrl();
    final token = ApiController.instance.accessToken?.trim() ?? '';
    final fileRef = XFile(filePath, name: fileName);
    final size = await fileRef.length();
    if (size <= 0) throw Exception('operation_failed'.tr);

    const maxChunkSize = 5 * 1024 * 1024;
    final chunkSize = size < maxChunkSize ? size : maxChunkSize;
    final totalChunks = (size + chunkSize - 1) ~/ chunkSize;
    final sessionHash = '${Uuid().v4()}_$chunkSize';

    for (var part = 0; part < totalChunks; part++) {
      if (cancelToken != null && cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: url),
          type: dio.DioExceptionType.cancel,
        );
      }

      final start = part * chunkSize;
      final end = (start + chunkSize) > size ? size : (start + chunkSize);
      final length = end - start;

      final api = ApiController.instance;
      final isP2p = api.isP2pMode;

      if (isP2p) {
        final bytesBuilder = BytesBuilder(copy: false);
        await for (final chunk in fileRef.openRead(start, end)) {
          bytesBuilder.add(chunk);
        }
        final chunkBytes = bytesBuilder.takeBytes();

        final req = http.MultipartRequest('POST', Uri.parse(url));
        if (token.isNotEmpty) {
          req.headers['authorization'] = 'Bearer $token';
        }
        req.headers['accept'] = 'application/json';
        req.fields['hash'] = sessionHash;
        req.fields['chunkSize'] = chunkSize.toString();
        req.fields['fileName'] = fileName;
        req.fields['totalChunks'] = totalChunks.toString();
        req.fields['index'] = part.toString();
        req.files.add(
          http.MultipartFile.fromBytes('file', chunkBytes, filename: 'chunk'),
        );

        final streamed = await api.sendP2pRequestOnChannel(
          req,
          timeout: const Duration(minutes: 5),
          channel: P2pRtcChannel.upload,
        );
        final respBytes = await http.ByteStream(streamed.stream).toBytes();
        final text = utf8.decode(respBytes, allowMalformed: true);
        dynamic decoded;
        try {
          decoded = jsonDecode(text);
        } catch (_) {
          decoded = {
            'success': false,
            'message': text,
            'code': streamed.statusCode,
          };
        }
        _ensureSuccess(decoded);
        onSendProgress?.call(end, size);
        continue;
      }

      final form = dio.FormData.fromMap({
        'hash': sessionHash,
        'chunkSize': chunkSize,
        'fileName': fileName,
        'totalChunks': totalChunks,
        'index': part,
        'file': dio.MultipartFile.fromStream(
          () => fileRef.openRead(start, end),
          length,
          filename: 'chunk',
        ),
      });

      final resp = await _dio.post(
        url,
        data: form,
        options: dio.Options(
          headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'},
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );
      _ensureSuccess(resp.data);
      onSendProgress?.call(end, size);
    }
  }

  String _buildChunkUploadUrl() {
    final baseUrl = ApiController.instance.baseUrl;
    final qp = <String, String>{
      'spaceId': spaceId.toString(),
      'spaceToken': token,
    };
    final accessToken = ApiController.instance.accessToken?.trim() ?? '';
    if (accessToken.isNotEmpty) qp['accessToken'] = accessToken;
    return Uri.parse(
      '$baseUrl/api/encryptedSpace/upload/chunk',
    ).replace(queryParameters: qp).toString();
  }

  void _ensureSuccess(dynamic data) {
    if (data is Map) {
      final ok = data['success'] == true || data['code'] == 0;
      if (ok) return;
      final apiKey = data['code'] is String ? data['code'] as String : null;
      final msg = data['message']?.toString().trim();
      throw _UploadServerException(
        ApiErrorLocalizer.localize(
          apiErrorKey: apiKey,
          serverMessage: msg?.isNotEmpty == true ? msg : null,
        ),
      );
    }
    throw _UploadServerException('operation_failed'.tr);
  }

  /// 从服务端错误或异常中取出可展示的文案（优先使用接口返回的 message）
  String _serverMessage(dynamic e) {
    if (e is dio.DioException) {
      final data = e.response?.data;
      if (data != null) {
        if (data is Map) {
          final apiKey = data['code'] is String ? data['code'] as String : null;
          final msg = data['message']?.toString().trim();
          return ApiErrorLocalizer.localize(
            apiErrorKey: apiKey,
            serverMessage: msg?.isNotEmpty == true ? msg : null,
          );
        } else if (data is String) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              final apiKey =
                  decoded['code'] is String ? decoded['code'] as String : null;
              final msg = decoded['message']?.toString().trim();
              return ApiErrorLocalizer.localize(
                apiErrorKey: apiKey,
                serverMessage: msg?.isNotEmpty == true ? msg : null,
              );
            }
          } catch (_) {}
        }
      }
      return e.message ?? 'operation_failed'.tr;
    }
    if (e is _UploadServerException) return e.message;
    final msg = e.toString().trim();
    if (msg.isNotEmpty) {
      const prefix = 'Exception: ';
      if (msg.startsWith(prefix)) return msg.substring(prefix.length);
      return msg;
    }
    return 'operation_failed'.tr;
  }

  void openItem(Map<String, dynamic> item) {
    final type = fileTypeOf(item);
    if (type == 'image') {
      _openImage(item);
      return;
    }
    if (type == 'video') {
      _openVideo(item);
      return;
    }
  }

  void _openImage(Map<String, dynamic> clicked) {
    final clickedId = indexIdOf(clicked);
    if (clickedId <= 0) return;

    final images = files
        .where((e) => fileTypeOf(e) == 'image')
        .map((e) {
          final id = indexIdOf(e);
          final name = displayNameOf(e);
          return <String, dynamic>{
            ...e,
            '_encryptedSpaceIndexId': id,
            'name': name,
            'url': buildDecodeUrl(indexId: id),
            'downloadUrl': buildDecodeUrl(
              indexId: id,
              download: true,
              fileName: name,
            ),
          };
        })
        .toList(growable: false);
    if (images.isEmpty) return;

    final index = images.indexWhere((e) {
      final id = e['_encryptedSpaceIndexId'];
      final n = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
      return n == clickedId;
    });
    if (index < 0) return;

    if (!Get.isRegistered<CustomGalleryController>()) {
      Get.put(CustomGalleryController());
    }
    final galleryCtrl = CustomGalleryController.instance;
    galleryCtrl.configure(
      showInfo: false,
      deleteHandler: (item, _) => deleteItemFromGalleryFlow(item),
      downloadHandler: (item, _) => downloadItemFromGallery(item),
    );
    galleryCtrl.isControlsVisible.value = true;
    galleryCtrl.galleryItems = images;
    galleryCtrl.galleryInitialIndex.value = index;

    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.openImageViewer(
        images,
        index,
        showInfo: false,
        deleteHandler: (item, _) => deleteItemFromGalleryFlow(item),
        downloadHandler: (item, _) => downloadItemFromGallery(item),
      );
      return;
    }
    Get.to(() => const CustomGallery());
  }

  void _openVideo(Map<String, dynamic> clicked) {
    final clickedId = indexIdOf(clicked);
    if (clickedId <= 0) return;

    final videos = files
        .where((e) => fileTypeOf(e) == 'video')
        .map(
          (e) => <String, dynamic>{
            '_encryptedSpaceIndexId': indexIdOf(e),
            'path': buildDecodeUrl(indexId: indexIdOf(e)),
            'name': displayNameOf(e),
          },
        )
        .toList(growable: false);
    if (videos.isEmpty) return;

    final index = videos.indexWhere((e) {
      final id = e['_encryptedSpaceIndexId'];
      final n = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
      return n == clickedId;
    });
    if (index < 0) return;

    AppRoutes.toVideoPlayer(playlist: videos, initialIndex: index);
  }
}

/// 上传时服务端返回的错误，用于携带并展示接口的 message 文案
class _UploadServerException implements Exception {
  final String message;
  _UploadServerException(this.message);
  @override
  String toString() => message;
}

class _EncryptedSpaceUploadEntry {
  final String fileName;
  final String? filePath;
  final dynamic webFile;

  const _EncryptedSpaceUploadEntry._({
    required this.fileName,
    this.filePath,
    this.webFile,
  });

  factory _EncryptedSpaceUploadEntry.path({
    required String fileName,
    required String filePath,
  }) {
    return _EncryptedSpaceUploadEntry._(fileName: fileName, filePath: filePath);
  }

  factory _EncryptedSpaceUploadEntry.webFile({
    required String fileName,
    required dynamic file,
  }) {
    return _EncryptedSpaceUploadEntry._(fileName: fileName, webFile: file);
  }
}
