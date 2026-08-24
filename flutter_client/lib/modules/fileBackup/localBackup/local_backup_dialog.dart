part of '../backupMain/file_backup_view.dart';

class _LocalBackupDialog extends StatefulWidget {
  final LocalBackupController ctrl;
  final LocalBackupProfile? initial;
  const _LocalBackupDialog({required this.ctrl, this.initial});

  @override
  State<_LocalBackupDialog> createState() => _LocalBackupDialogState();
}

class _LocalBackupDialogState extends State<_LocalBackupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _excludeCtrl;

  bool _realtime = false;
  bool _enabled = true;
  String _sourceBookmark = '';
  bool _saving = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl = TextEditingController(text: init?.name ?? '');
    _sourceCtrl = TextEditingController(text: init?.sourceDir ?? '');
    _targetCtrl = TextEditingController(text: init?.targetDir ?? '');
    _intervalCtrl = TextEditingController(
      text: (init?.intervalMinutes ?? 60).toString(),
    );
    _excludeCtrl = TextEditingController(
      text: (init?.excludeItems ?? const []).join('\n'),
    );
    _realtime = init?.realtime ?? false;
    _enabled = init?.enabled ?? true;
    _sourceBookmark = (init?.sourceBookmark ?? '').trim();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    _intervalCtrl.dispose();
    _excludeCtrl.dispose();
    super.dispose();
  }

  int _parsePositiveInt(String s, {required int fallback}) {
    final v = int.tryParse(s.trim());
    if (v == null || v <= 0) return fallback;
    return v;
  }

  Future<void> _pickLocalSource() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return;
    final nextPath = path.trim();
    _sourceCtrl.text = nextPath;
    if (DeviceUtils.isMacOS) {
      final bookmark = await widget.ctrl.createMacOSBookmarkForPath(nextPath);
      _sourceBookmark = bookmark?.trim() ?? '';
    }
  }

  Future<void> _pickTargetDir() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _targetCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    _targetCtrl.text = res.first.trim();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final source = _sourceCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    final intervalMinutes = _parsePositiveInt(_intervalCtrl.text, fallback: 60);
    final excludeItems = _excludeCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    const debounceSeconds = 30;
    final initNameStrategy = widget.initial?.nameStrategy ?? '';
    final nameStrategy = initNameStrategy.trim().isNotEmpty
        ? initNameStrategy.trim()
        : 'overwrite';

    setState(() => _saving = true);
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final access = await widget.ctrl.checkTargetDirFsAccess(target);
      if (access == null) {
        ToastUtil.show('local_backup_target_permission_check_failed'.tr);
        return;
      }
      final exists = access['exists'] == true;
      final isDirectory = access['isDirectory'] == true;
      if (!exists || !isDirectory) {
        ToastUtil.show('local_backup_target_permission_check_failed'.tr);
        return;
      }
      final canRead = access['canRead'] == true;
      final canWrite = access['canWrite'] == true;
      if (!canRead) {
        ToastUtil.show('local_backup_target_no_read_permission'.tr);
        return;
      }
      if (!canWrite) {
        ToastUtil.show('local_backup_target_no_write_permission'.tr);
        return;
      }

      final ok = await widget.ctrl.upsertProfile(
        id: widget.initial?.id,
        name: _nameCtrl.text.trim(),
        sourceDir: source,
        sourceBookmark: DeviceUtils.isMacOS ? _sourceBookmark : null,
        targetDir: target,
        excludeItems: excludeItems,
        realtime: _realtime,
        intervalMinutes: intervalMinutes,
        debounceSeconds: debounceSeconds,
        nameStrategy: nameStrategy,
        enabled: _enabled,
      );
      if (!ok) return;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      DialogUtil.dismissLoading(force: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_saving,
      child: DialogUtil.createAlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                _isEdit ? 'local_backup_edit'.tr : 'local_backup_create'.tr,
              ),
            ),
            if (!_isEdit)
              Tooltip(
                message: 'local_backup_upload_strategy_tooltip'.tr,
                child: const Icon(Icons.help_outline, size: 18),
              ),
          ],
        ),
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 360),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: _nameCtrl,
                  labelText: 'name'.tr,
                  hintText: 'local_backup_name_hint'.tr,
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _sourceCtrl,
                  labelText: 'local_backup_source_dir'.tr,
                  hintText: 'choose_path'.tr,
                  enabled: !_saving,
                  readOnly: true,
                  onTap: _saving ? null : _pickLocalSource,
                  suffixIcon: const Icon(Icons.folder_open_outlined),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _targetCtrl,
                  labelText: 'local_backup_target_dir'.tr,
                  hintText: 'local_backup_pick_target'.tr,
                  enabled: !_saving,
                  readOnly: true,
                  onTap: _saving ? null : _pickTargetDir,
                  suffixIcon: const Icon(Icons.cloud_outlined),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _excludeCtrl,
                  labelText: 'local_backup_exclude'.tr,
                  hintText: 'local_backup_exclude_hint'.tr,
                  enabled: !_saving,
                  maxLines: 4,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'local_backup_exclude_help'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  activeColor: Theme.of(context).colorScheme.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text('local_backup_auto_backup'.tr),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (v) {
                          setState(() => _enabled = v);
                        },
                ),
                if (_enabled) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    activeColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text('local_backup_realtime'.tr),
                    value: _realtime,
                    onChanged: _saving
                        ? null
                        : (v) {
                            setState(() => _realtime = v);
                          },
                  ),
                  const SizedBox(height: 8),
                  if (!_realtime)
                    CustomTextField(
                      controller: _intervalCtrl,
                      labelText: 'local_backup_interval_minutes'.tr,
                      hintText: 'input_please'.tr,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Get.back(),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
  }
}
