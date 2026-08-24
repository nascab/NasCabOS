part of '../backupMain/file_backup_view.dart';

class _ServerBackupDialog extends StatefulWidget {
  final FileBackupController ctrl;
  final Map<String, dynamic>? initial;
  const _ServerBackupDialog({required this.ctrl, this.initial});

  @override
  State<_ServerBackupDialog> createState() => _ServerBackupDialogState();
}

class _ServerBackupDialogState extends State<_ServerBackupDialog> {
  late final TextEditingController _sourcesCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _freqCtrl;
  late final TextEditingController _excludeCtrl;

  List<String> _sources = const [];
  String _type = 'copy';
  bool _saving = false;
  static const int _minFreqHours = 1;
  static const int _maxFreqHours = 8760;

  bool get _isEdit => widget.initial != null;
  bool get _isRunning =>
      (widget.initial?['status']?.toString() ?? '').trim().toLowerCase() ==
      'running';

  @override
  void initState() {
    super.initState();
    final initSources = () {
      final v = widget.initial?['source_path'];
      if (v is List) {
        return v
            .map((e) => e?.toString() ?? '')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return <String>[];
    }();
    final initExclude = () {
      final v = widget.initial?['exclude_list'];
      if (v is List) {
        return v
            .map((e) => e?.toString() ?? '')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return <String>[];
    }();
    final initType =
        widget.initial?['type']?.toString().trim().toLowerCase() ?? 'copy';
    final initTarget = widget.initial?['target_path']?.toString() ?? '';
    final initFreq =
        (int.tryParse(widget.initial?['frenquence']?.toString() ?? '') ?? 24)
            .toString();

    _sources = initSources;
    _type = initType == 'sync' ? 'sync' : 'copy';

    _sourcesCtrl = TextEditingController(text: _sourcesText(_sources));
    _targetCtrl = TextEditingController(text: initTarget);
    _freqCtrl = TextEditingController(text: initFreq);
    _excludeCtrl = TextEditingController(text: initExclude.join('\n'));
  }

  @override
  void dispose() {
    _sourcesCtrl.dispose();
    _targetCtrl.dispose();
    _freqCtrl.dispose();
    _excludeCtrl.dispose();
    super.dispose();
  }

  String _sourcesText(List<String> sources) {
    if (sources.isEmpty) return '';
    if (sources.length == 1) return sources.first;
    return '${sources.first} (+${sources.length - 1})';
  }

  Future<void> _pickSources() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: true,
      allowFileSelect: false,
      initialPath: _sources.isNotEmpty ? _sources.first : null,
    );
    if (res == null || res.isEmpty) return;
    final picked = res
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (picked.isEmpty) return;
    setState(() {
      final merged = <String>[];
      final seen = <String>{};
      for (final p in [..._sources, ...picked]) {
        if (seen.add(p)) merged.add(p);
      }
      _sources = merged;
      _sourcesCtrl.text = _sourcesText(_sources);
    });
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

  List<String> _parseExcludeList(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final parts = t.split(RegExp(r'[\n,]'));
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  int _parseFreq() {
    return int.tryParse(_freqCtrl.text.trim()) ?? 0;
  }

  int _clampFreq(int v) {
    if (v < _minFreqHours) return _minFreqHours;
    if (v > _maxFreqHours) return _maxFreqHours;
    return v;
  }

  void _setFreq(int v) {
    _freqCtrl.text = _clampFreq(v).toString();
  }

  void _stepFreq(int delta) {
    final current = _parseFreq();
    final next = _clampFreq((current <= 0 ? _minFreqHours : current) + delta);
    _setFreq(next);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = int.tryParse(widget.initial?['id']?.toString() ?? '');
    final target = _targetCtrl.text.trim();
    final freq = _clampFreq(int.tryParse(_freqCtrl.text.trim()) ?? 0);
    final excludes = _parseExcludeList(_excludeCtrl.text);

    if (_sources.isEmpty || target.isEmpty || freq <= 0) {
      DialogUtil.showErrorDialog(message: 'file_backup_required'.tr);
      return;
    }

    _setFreq(freq);

    setState(() => _saving = true);
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final ok = await widget.ctrl.upsert(
        id: _isEdit ? id : null,
        sourcePathList: _sources,
        type: _type,
        targetPath: target,
        frenquence: freq,
        excludeList: excludes,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _saving = false);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_saving,
      child: DialogUtil.createAlertDialog(
        title: Text(_isEdit ? 'file_backup_edit'.tr : 'file_backup_create'.tr),
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in _sources)
                        InputChip(
                          label: Text(p, overflow: TextOverflow.ellipsis),
                          onDeleted: _isRunning || _saving
                              ? null
                              : () {
                                  setState(() {
                                    _sources = _sources
                                        .where((e) => e != p)
                                        .toList();
                                    _sourcesCtrl.text = _sourcesText(_sources);
                                  });
                                },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text('file_backup_pick_source'.tr),
                        onPressed: _isRunning || _saving
                            ? null
                            : () => _pickSources(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                CustomTextField(
                  controller: _targetCtrl,
                  labelText: 'file_backup_target_path'.tr,
                  hintText: 'file_backup_pick_target'.tr,
                  enabled: !_isRunning && !_saving,
                  readOnly: true,
                  onTap: _isRunning || _saving ? null : _pickTarget,
                  suffixIcon: const Icon(Icons.folder_outlined),
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _type,
                  labelText: 'file_backup_type'.tr,
                  enabled: !_isRunning && !_saving,
                  items: [
                    DropdownMenuItem(
                      value: 'copy',
                      child: Text('file_backup_type_copy'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'sync',
                      child: Text('file_backup_type_sync'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = v?.toString() ?? '';
                    if (next != 'copy' && next != 'sync') return;
                    setState(() => _type = next);
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (_type == 'sync'
                            ? 'file_backup_type_desc_sync'
                            : 'file_backup_type_desc_copy')
                        .tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _freqCtrl,
                        labelText: 'file_backup_frequency_hours'.tr,
                        hintText: 'input_please'.tr,
                        enabled: !_isRunning && !_saving,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CustomIconButton(
                      icon: Icons.remove,
                      onPressed: (_isRunning || _saving)
                          ? null
                          : () => _stepFreq(-1),
                      buttonSize: 40,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 8),
                    CustomIconButton(
                      icon: Icons.add,
                      onPressed: (_isRunning || _saving)
                          ? null
                          : () => _stepFreq(1),
                      buttonSize: 40,
                      iconSize: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _excludeCtrl,
                  labelText: 'file_backup_exclude_list'.tr,
                  hintText: 'input_please'.tr,
                  enabled: !_isRunning && !_saving,
                  maxLines: 4,
                ),
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
            onPressed: (_isRunning || _saving) ? null : _submit,
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
  }
}
