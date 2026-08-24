import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart' as pm;

import '../../../modules/base/components/custom_icon_button.dart';
import '../../../modules/base/components/custom_no_data.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../transfer/controllers/upload_parts/upload_transfer_helper.dart';
import '../controller/photo_backup_controller.dart';
import '../models/photo_backup_models.dart';
import 'photo_backup_album_picker_sheet.dart';

class AppPhotoBackupView extends GetView<PhotoBackupController> {
  const AppPhotoBackupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('home_photo_backup'.tr),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CustomIconButton(
              icon: Icons.add,
              onPressed: () => _openTaskForm(context),
              tooltip: 'photo_backup_create'.tr,
              iconColor: Colors.white,
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.loading.value && controller.tasks.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.tasks.isEmpty) {
          return RefreshIndicator(
            onRefresh: controller.refreshTasks,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                CustomNoData(text: 'photo_backup_empty_hint'.tr),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: controller.refreshTasks,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            itemCount: controller.tasks.length,
            itemBuilder: (context, index) {
              final task = controller.tasks[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TaskCard(task: task),
              );
            },
          ),
        );
      }),
    );
  }

  Future<void> _openTaskForm(
    BuildContext context, {
    PhotoBackupTask? initial,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoBackupTaskFormView(initial: initial),
      ),
    );
  }
}

class _TaskCard extends GetView<PhotoBackupController> {
  final PhotoBackupTask task;
  const _TaskCard({required this.task});

  String _statusText(PhotoBackupRuntime rt) {
    if (rt.running.value) return 'local_backup_status_running'.tr;
    if (rt.status.value == 'error') return 'local_backup_status_error'.tr;
    return 'local_backup_status_idle'.tr;
  }

  String _sourceTypeText(PhotoBackupTask task) {
    return task.sourceType == PhotoBackupSourceType.album
        ? 'photo_backup_source_album'.tr
        : 'photo_backup_source_folder'.tr;
  }

  String _saveTypeText(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'day') return 'upload_center_save_type_day'.tr;
    if (v == 'month') return 'upload_center_save_type_month'.tr;
    if (v == 'year') return 'upload_center_save_type_year'.tr;
    return 'upload_center_save_type_root'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rt = controller.runtimeOf(task.id);
    return Obx(() {
      return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showActions(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusText(rt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: rt.running.value
                            ? theme.colorScheme.primary
                            : (rt.status.value == 'error'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kv(
                  context,
                  'photo_backup_source'.tr,
                  '${_sourceTypeText(task)} · ${task.sourceName}',
                ),
                const SizedBox(height: 4),
                _kv(context, 'photo_backup_target'.tr, task.targetDir),
                const SizedBox(height: 4),
                _kv(context, 'folder_name_strategy'.tr, task.nameStrategy.tr),
                const SizedBox(height: 4),
                _kv(
                  context,
                  'upload_center_save_type'.tr,
                  _saveTypeText(task.saveType),
                ),
                if (rt.running.value) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: rt.progress, minHeight: 6),
                  const SizedBox(height: 6),
                  Text(
                    'photo_backup_progress'.trParams({
                      'done': '${rt.doneFiles.value}',
                      'total': rt.totalFiles.value > 0
                          ? '${rt.totalFiles.value}'
                          : '-',
                      'bytesDone': UploadTransferHelper.formatBytes(
                        rt.doneBytes.value,
                      ),
                      'bytesTotal': rt.totalBytes.value > 0
                          ? UploadTransferHelper.formatBytes(
                              rt.totalBytes.value,
                            )
                          : '-',
                    }),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (rt.currentFile.value.trim().isNotEmpty)
                    Text(
                      rt.currentFile.value.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if (rt.error.value.trim().isNotEmpty && !rt.running.value) ...[
                  const SizedBox(height: 6),
                  Text(
                    rt.error.value.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final rt = controller.runtimeOf(task.id);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: rt.running.value
                    ? null
                    : () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                _PhotoBackupTaskFormView(initial: task),
                          ),
                        );
                      },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text('photo_backup_upload_new'.tr),
                onTap: () async {
                  Navigator.pop(context);
                  await controller.runUploadNew(task.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: Text('photo_backup_upload_all'.tr),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'need_confirm'.tr,
                    content: 'photo_backup_upload_all_confirm'.tr,
                    confirmText: 'ok'.tr,
                    cancelText: 'cancel'.tr,
                  );
                  if (ok == true) {
                    await controller.runUploadAll(task.id);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text('photo_backup_runs'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _showRunsDialog(context, task);
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt_outlined),
                title: Text('photo_backup_file_logs'.tr),
                onTap: () {
                  Navigator.pop(context);
                  _showRunsDialog(context, task, openLatestFiles: true);
                },
              ),
              if (rt.running.value)
                ListTile(
                  leading: const Icon(Icons.stop_circle_outlined),
                  title: Text('file_backup_stop'.tr),
                  onTap: () {
                    Navigator.pop(context);
                    controller.cancelTask(task.id);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: rt.running.value
                    ? null
                    : () async {
                        Navigator.pop(context);
                        final ok = await DialogUtil.showConfirmDialog(
                          title: 'need_confirm'.tr,
                          content: 'photo_backup_delete_task_confirm'.trParams({
                            'name': task.name,
                          }),
                          confirmText: 'ok'.tr,
                          cancelText: 'cancel'.tr,
                        );
                        if (ok == true) {
                          await controller.deleteTask(task.id);
                        }
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRunsDialog(
    BuildContext context,
    PhotoBackupTask task, {
    bool openLatestFiles = false,
  }) async {
    final runs = await controller.listRuns(task.id);
    if (runs.isEmpty) {
      ToastUtil.show('no_data'.tr);
      return;
    }
    if (openLatestFiles) {
      if (!context.mounted) return;
      await _showRunFilesDialog(context, runs.first);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RunRecordsDialog(
        taskName: task.name,
        runs: runs,
        onOpenFiles: (run) => _showRunFilesDialog(context, run),
        onDeleteRun: (run) async {
          await controller.deleteRun(run.id);
          await controller.refreshTasks();
        },
      ),
    );
  }

  Future<void> _showRunFilesDialog(
    BuildContext context,
    PhotoBackupRunRecord run,
  ) async {
    final files = await controller.listRunFiles(run.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RunFilesDialog(run: run, files: files),
    );
  }
}

class _RunRecordsDialog extends StatefulWidget {
  final String taskName;
  final List<PhotoBackupRunRecord> runs;
  final Future<void> Function(PhotoBackupRunRecord run) onOpenFiles;
  final Future<void> Function(PhotoBackupRunRecord run) onDeleteRun;

  const _RunRecordsDialog({
    required this.taskName,
    required this.runs,
    required this.onOpenFiles,
    required this.onDeleteRun,
  });

  @override
  State<_RunRecordsDialog> createState() => _RunRecordsDialogState();
}

class _RunRecordsDialogState extends State<_RunRecordsDialog> {
  late List<PhotoBackupRunRecord> _runs;

  @override
  void initState() {
    super.initState();
    _runs = widget.runs.toList();
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'photo_backup_runs_title'.trParams({'name': widget.taskName}),
      ),
      content: SizedBox(
        width: 720,
        height: 420,
        child: _runs.isEmpty
            ? Center(child: Text('no_data'.tr))
            : ListView.separated(
                itemCount: _runs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final run = _runs[i];
                  return ListTile(
                    title: Text(
                      'photo_backup_run_item'.trParams({
                        'success': '${run.successCount}',
                        'failed': '${run.failedCount}',
                      }),
                    ),
                    subtitle: Text(
                      '${_fmtTime(run.startedAtMs)} - ${_fmtTime(run.finishedAtMs)}\n${UploadTransferHelper.formatBytes(run.totalBytes)}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          tooltip: 'photo_backup_file_logs'.tr,
                          onPressed: () => widget.onOpenFiles(run),
                          icon: const Icon(Icons.list_alt_outlined),
                        ),
                        IconButton(
                          tooltip: 'delete'.tr,
                          onPressed: () async {
                            await widget.onDeleteRun(run);
                            if (!mounted) return;
                            setState(() {
                              _runs.removeWhere((e) => e.id == run.id);
                            });
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}

class _RunFilesDialog extends StatelessWidget {
  final PhotoBackupRunRecord run;
  final List<PhotoBackupFileRecord> files;

  const _RunFilesDialog({required this.run, required this.files});

  String _fmtTime(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'photo_backup_file_logs_title'.trParams({
          'time': _fmtTime(run.startedAtMs),
        }),
      ),
      content: SizedBox(
        width: 760,
        height: 420,
        child: files.isEmpty
            ? Center(child: Text('no_data'.tr))
            : ListView.separated(
                itemCount: files.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final item = files[i];
                  final failed = item.status == 'error';
                  return ListTile(
                    leading: Icon(
                      failed ? Icons.error_outline : Icons.check_circle_outline,
                      color: failed ? Colors.red : Colors.green,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      '${UploadTransferHelper.formatBytes(item.size)} · ${_fmtTime(item.uploadedAtMs)}${item.error.isEmpty ? '' : '\n${item.error}'}',
                    ),
                    isThreeLine: item.error.isNotEmpty,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}

class _PhotoBackupTaskFormView extends StatefulWidget {
  final PhotoBackupTask? initial;
  const _PhotoBackupTaskFormView({this.initial});

  @override
  State<_PhotoBackupTaskFormView> createState() =>
      _PhotoBackupTaskFormViewState();
}

class _PhotoBackupTaskFormViewState extends State<_PhotoBackupTaskFormView> {
  late final TextEditingController _targetCtrl;
  PhotoBackupSourceType? _sourceType;
  String _sourceId = '';
  String _sourceName = '';
  String _nameStrategy = 'skip';
  String _saveType = '';
  bool _uploadLivePhotoVideo = false;
  bool _autoStartOnLaunch = false;
  bool _saving = false;

  PhotoBackupController get _ctrl => Get.find<PhotoBackupController>();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _targetCtrl = TextEditingController(text: initial?.targetDir ?? '');
    _sourceType = initial?.sourceType;
    _sourceId = initial?.sourceId ?? '';
    _sourceName = initial?.sourceName ?? '';
    _nameStrategy = initial?.nameStrategy ?? 'skip';
    _saveType = initial?.saveType ?? '';
    _uploadLivePhotoVideo = initial?.uploadLivePhotoVideo ?? false;
    _autoStartOnLaunch = initial?.autoStartOnLaunch ?? false;
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDir() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _targetCtrl.text.trim().isEmpty ? null : _targetCtrl.text,
    );
    if (res == null || res.isEmpty) return;
    _targetCtrl.text = res.first.trim();
    setState(() {});
  }

  /// 请求相册权限，兼容 Android / iOS。
  /// 使用 [pm.PhotoManager.requestPermissionExtend]，与枚举相册及上传中心一致；
  /// 避免 iOS 上 permission_handler 的 [Permission.photos] 与 Photos 框架状态不一致导致误报未授权。
  /// 返回 true 表示已授权（含「选择的照片」限权），false 表示未授权（已弹引导）。
  Future<bool> _requestPhotoPermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return true;
    }
    final pm.PermissionState state =
        await pm.PhotoManager.requestPermissionExtend();
    if (state.hasAccess) return true;

    if (!mounted) return false;
    ToastUtil.show('photo_library_permission_missing'.tr);
    return false;
  }

  Future<void> _pickSource() async {
    final granted = await _requestPhotoPermission();
    if (!granted) return;
    if (!mounted) return;
    final picked = await showPhotoBackupAlbumPicker(context);
    if (picked == null) return;
    _sourceType = PhotoBackupSourceType.album;
    _sourceId = picked.id;
    _sourceName = picked.name.trim().isEmpty ? 'album' : picked.name.trim();
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_sourceType == null ||
        _sourceId.trim().isEmpty ||
        _targetCtrl.text.trim().isEmpty) {
      ToastUtil.show('photo_backup_required'.tr);
      return;
    }
    setState(() => _saving = true);
    try {
      final ok = await _ctrl.saveTask(
        id: widget.initial?.id,
        sourceType: _sourceType!,
        sourceId: _sourceId.trim(),
        sourceName: _sourceName.trim(),
        targetDir: _targetCtrl.text.trim(),
        nameStrategy: _nameStrategy,
        saveType: _saveType,
        uploadLivePhotoVideo: _uploadLivePhotoVideo,
        autoStartOnLaunch: _autoStartOnLaunch,
      );
      if (!ok) return;
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null
              ? 'photo_backup_create'.tr
              : 'photo_backup_edit'.tr,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        children: [
          _lineCard(
            context,
            icon: Icons.source_outlined,
            title: 'photo_backup_source'.tr,
            subtitle: _sourceType == null
                ? 'photo_backup_source_empty'.tr
                : '${_sourceType == PhotoBackupSourceType.album ? 'photo_backup_source_album'.tr : 'photo_backup_source_folder'.tr} · $_sourceName',
            onTap: _pickSource,
          ),
          const SizedBox(height: 10),
          _lineCard(
            context,
            icon: Icons.folder_open_outlined,
            title: 'photo_backup_target'.tr,
            subtitle: _targetCtrl.text.trim().isEmpty
                ? 'quick_share_path_hint'.tr
                : _targetCtrl.text.trim(),
            onTap: _pickTargetDir,
          ),
          const SizedBox(height: 12),
          Text('folder_name_strategy'.tr, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final v in const ['skip', 'overwrite', 'rename'])
                ChoiceChip(
                  label: Text(v.tr),
                  selected: _nameStrategy == v,
                  onSelected: (_) => setState(() => _nameStrategy = v),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('upload_center_save_type'.tr, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _saveType,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('upload_center_save_type_root'.tr),
              ),
              DropdownMenuItem(
                value: 'day',
                child: Text('upload_center_save_type_day'.tr),
              ),
              DropdownMenuItem(
                value: 'month',
                child: Text('upload_center_save_type_month'.tr),
              ),
              DropdownMenuItem(
                value: 'year',
                child: Text('upload_center_save_type_year'.tr),
              ),
            ],
            onChanged: (v) {
              setState(() => _saveType = v ?? '');
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            activeColor: theme.colorScheme.primary,
            value: _uploadLivePhotoVideo,
            onChanged: (v) => setState(() => _uploadLivePhotoVideo = v),
            title: Text('photo_backup_upload_livephoto_video'.tr),
            subtitle: Text(
              'photo_backup_upload_livephoto_video_hint'.tr,
              style: theme.textTheme.bodySmall,
            ),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            activeColor: theme.colorScheme.primary,
            value: _autoStartOnLaunch,
            onChanged: (v) => setState(() => _autoStartOnLaunch = v),
            title: Text('photo_backup_auto_start'.tr),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'loading'.tr : 'save'.tr),
          ),
        ),
      ),
    );
  }

  Widget _lineCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
