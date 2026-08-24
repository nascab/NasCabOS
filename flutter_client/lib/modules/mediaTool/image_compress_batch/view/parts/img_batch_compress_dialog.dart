part of '../img_batch_compress_view.dart';

class _ImgBatchCompressDialog extends StatefulWidget {
  final ImgBatchCompressController ctrl;
  final Map<String, dynamic>? initial;
  const _ImgBatchCompressDialog({required this.ctrl, this.initial});

  @override
  State<_ImgBatchCompressDialog> createState() =>
      _ImgBatchCompressDialogState();
}

class _ImgBatchCompressDialogState extends State<_ImgBatchCompressDialog> {
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _qualityCtrl;
  late final TextEditingController _customSizeCtrl;

  String _format = 'jpeg';
  String _sizeMode = 'keep';
  int? _outSize;
  String _nonImagePolicy = 'skip';
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
    final initFormat = (widget.initial?['out_format']?.toString() ?? 'jpeg')
        .trim()
        .toLowerCase();
    final initQ =
        int.tryParse(widget.initial?['quality']?.toString() ?? '') ?? 80;
    final initOutSize = widget.initial?['out_size'];
    final initSize = initOutSize == null
        ? null
        : int.tryParse(initOutSize.toString());
    final initPol = (widget.initial?['non_image_policy']?.toString() ?? 'skip')
        .trim()
        .toLowerCase();

    _format =
        (initFormat == 'png' || initFormat == 'webp' || initFormat == 'jpeg')
        ? initFormat
        : 'jpeg';
    _outSize = initSize != null && initSize > 0 ? initSize : null;
    _sizeMode = _outSize == null ? 'keep' : 'custom';
    _nonImagePolicy = initPol == 'copy' ? 'copy' : 'skip';

    _sourceCtrl = TextEditingController(text: initSource);
    _targetCtrl = TextEditingController(text: initTarget);
    _qualityCtrl = TextEditingController(text: initQ.clamp(30, 100).toString());
    _customSizeCtrl = TextEditingController(
      text: _outSize == null ? '' : _outSize.toString(),
    );
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    _qualityCtrl.dispose();
    _customSizeCtrl.dispose();
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

  int _parseQuality() {
    final raw = _qualityCtrl.text.trim();
    if (raw.isEmpty) return 80;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits) ?? 0;
    return n.clamp(30, 100);
  }

  int? _parseOutSize() {
    if (_sizeMode == 'keep') return null;
    final raw = _customSizeCtrl.text.trim();
    final n = int.tryParse(raw);
    if (n == null) return null;
    return n.clamp(10, 20000);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = int.tryParse(widget.initial?['id']?.toString() ?? '');
    final source = _sourceCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    if (source.isEmpty || target.isEmpty) {
      DialogUtil.showErrorDialog(message: 'media_tool_img_batch_required'.tr);
      return;
    }

    setState(() => _saving = true);
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final ok = await widget.ctrl.upsert(
        id: _isEdit ? id : null,
        sourcePath: source,
        targetPath: target,
        outFormat: _format,
        quality: _parseQuality(),
        outSize: _parseOutSize(),
        nonImagePolicy: _nonImagePolicy,
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
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: () async => !_saving,
      child: DialogUtil.createAlertDialog(
        title: Text(_isEdit ? 'edit'.tr : 'create'.tr),
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 360),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: _sourceCtrl,
                  labelText: 'media_tool_img_batch_source'.tr,
                  hintText: 'media_tool_img_batch_pick_source'.tr,
                  enabled: !_isRunning && !_saving,
                  readOnly: true,
                  onTap: _isRunning || _saving ? null : _pickSource,
                  suffixIcon: const Icon(Icons.folder_outlined),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _targetCtrl,
                  labelText: 'media_tool_img_batch_target'.tr,
                  hintText: 'media_tool_img_batch_pick_target'.tr,
                  enabled: !_isRunning && !_saving,
                  readOnly: true,
                  onTap: _isRunning || _saving ? null : _pickTarget,
                  suffixIcon: const Icon(Icons.folder_outlined),
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _format,
                  labelText: 'media_tool_format'.tr,
                  enabled: !_isRunning && !_saving,
                  items: const [
                    DropdownMenuItem(value: 'jpeg', child: Text('JPEG')),
                    DropdownMenuItem(value: 'png', child: Text('PNG')),
                    DropdownMenuItem(value: 'webp', child: Text('WEBP')),
                  ],
                  onChanged: (v) {
                    final next = v?.toString() ?? '';
                    if (next != 'jpeg' && next != 'png' && next != 'webp') {
                      return;
                    }
                    setState(() => _format = next);
                  },
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _qualityCtrl,
                  labelText: 'media_tool_quality'.tr,
                  enabled: !_isRunning && !_saving,
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    final raw = _qualityCtrl.text;
                    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.isEmpty) return;
                    final n = int.tryParse(digits) ?? 0;
                    final next = n.clamp(30, 100).toString();
                    if (next == raw) return;
                    _qualityCtrl.value = _qualityCtrl.value.copyWith(
                      text: next,
                      selection: TextSelection.collapsed(offset: next.length),
                      composing: TextRange.empty,
                    );
                  },
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _sizeMode,
                  labelText: 'media_tool_out_size'.tr,
                  enabled: !_isRunning && !_saving,
                  items: [
                    DropdownMenuItem(
                      value: 'keep',
                      child: Text('media_tool_img_batch_keep_size'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text('media_tool_custom_size'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = v?.toString() ?? '';
                    if (next != 'keep' && next != 'custom') return;
                    setState(() => _sizeMode = next);
                  },
                ),
                if (_sizeMode == 'custom') ...[
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _customSizeCtrl,
                    labelText: 'media_tool_custom_size'.tr,
                    hintText: 'media_tool_out_size_hint'.tr,
                    enabled: !_isRunning && !_saving,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      final raw = _customSizeCtrl.text;
                      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.isEmpty) {
                        if (raw.isEmpty) return;
                        _customSizeCtrl.clear();
                        return;
                      }
                      final n = int.tryParse(digits) ?? 0;
                      final next = n.clamp(10, 20000).toString();
                      if (next == raw) return;
                      _customSizeCtrl.value = _customSizeCtrl.value.copyWith(
                        text: next,
                        selection: TextSelection.collapsed(offset: next.length),
                        composing: TextRange.empty,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _nonImagePolicy,
                  labelText: 'media_tool_img_batch_non_image'.tr,
                  enabled: !_isRunning && !_saving,
                  items: [
                    DropdownMenuItem(value: 'skip', child: Text('skip'.tr)),
                    DropdownMenuItem(
                      value: 'copy',
                      child: Text('media_tool_img_batch_non_image_copy'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = v?.toString() ?? '';
                    if (next != 'skip' && next != 'copy') return;
                    setState(() => _nonImagePolicy = next);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: _saving ? null : _submit,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }
}
