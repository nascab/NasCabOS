part of '../media_arrange_view.dart';

class _MediaArrangeDialog extends StatefulWidget {
  final MediaArrangeController ctrl;
  final Map<String, dynamic>? initial;
  const _MediaArrangeDialog({required this.ctrl, this.initial});

  @override
  State<_MediaArrangeDialog> createState() => _MediaArrangeDialogState();
}

class _MediaArrangeDialogState extends State<_MediaArrangeDialog> {
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _targetCtrl;

  String _arrangeType = 'day';
  String _sameNamePolicy = 'rename';
  bool _saving = false;

  bool get _isEdit => widget.initial != null;
  bool get _isRunning =>
      (widget.initial?['status']?.toString() ?? '').trim().toLowerCase() ==
      'running';

  @override
  void initState() {
    super.initState();
    final initSource = widget.initial?['source_path']?.toString() ?? '';
    final initTarget = widget.initial?['target_path']?.toString() ?? '';
    final initType = widget.initial?['arrange_type']?.toString() ?? 'day';
    final initSameNamePolicy =
        widget.initial?['same_name_policy']?.toString() ?? 'rename';

    _sourceCtrl = TextEditingController(text: initSource);
    _targetCtrl = TextEditingController(text: initTarget);

    if (['year', 'month', 'day'].contains(initType)) {
      _arrangeType = initType;
    }
    if (['skip', 'rename', 'overwrite'].contains(initSameNamePolicy)) {
      _sameNamePolicy = initSameNamePolicy;
    }
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _sourceCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    _sourceCtrl.text = res.first;
  }

  Future<void> _pickTarget() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _targetCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    _targetCtrl.text = res.first;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final s = _sourceCtrl.text.trim();
    final t = _targetCtrl.text.trim();
    if (s.isEmpty || t.isEmpty) {
      DialogUtil.showErrorDialog(message: 'media_tool_arrange_required'.tr);
      return;
    }

    setState(() => _saving = true);
    try {
      final success = await widget.ctrl.upsert(
        id: widget.initial?['id'],
        sourcePath: s,
        targetPath: t,
        arrangeType: _arrangeType,
        sameNamePolicy: _sameNamePolicy,
      );
      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _isRunning || _saving;
    return DialogUtil.createAlertDialog(
      title: Text(
        _isEdit
            ? 'edit'.tr
            : '${'create'.tr} ${'media_tool_menu_media_arrange'.tr}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 300,
          maxWidth: 500,
          maxHeight: 600,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isRunning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'media_tool_arrange_status_running_edit_hint'.tr,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              CustomTextField(
                controller: _sourceCtrl,
                labelText: 'media_tool_arrange_source'.tr,
                hintText: 'media_tool_arrange_pick_source'.tr,
                enabled: !disabled,
                readOnly: true,
                onTap: disabled ? null : _pickSource,
                suffixIcon: const Icon(Icons.folder_outlined),
              ),
              const SizedBox(height: 12),

              CustomTextField(
                controller: _targetCtrl,
                labelText: 'media_tool_arrange_target'.tr,
                hintText: 'media_tool_arrange_pick_target'.tr,
                enabled: !disabled,
                readOnly: true,
                onTap: disabled ? null : _pickTarget,
                suffixIcon: const Icon(Icons.folder_outlined),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'media_tool_arrange_target_hint'.tr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Arrange Type
              Text('media_tool_arrange_type'.tr),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _arrangeType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'year',
                    child: Text('media_tool_arrange_type_year'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'month',
                    child: Text('media_tool_arrange_type_month'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'day',
                    child: Text('media_tool_arrange_type_day'.tr),
                  ),
                ],
                onChanged: _isRunning
                    ? null
                    : (v) {
                        if (v != null) setState(() => _arrangeType = v);
                      },
              ),
              const SizedBox(height: 16),
              Text('media_tool_arrange_same_name_policy'.tr),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _sameNamePolicy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: [
                  DropdownMenuItem(value: 'skip', child: Text('skip'.tr)),
                  DropdownMenuItem(value: 'rename', child: Text('rename'.tr)),
                  DropdownMenuItem(
                    value: 'overwrite',
                    child: Text('overwrite'.tr),
                  ),
                ],
                onChanged: _isRunning
                    ? null
                    : (v) {
                        if (v != null) setState(() => _sameNamePolicy = v);
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('cancel'.tr),
        ),
        CustomButton(
          onPressed: _isRunning || _saving ? null : _submit,
          text: _saving ? 'media_tool_arrange_saving'.tr : 'ok'.tr,
        ),
      ],
    );
  }
}
