part of '../audio_trans_view.dart';

class _AudioTransDialog extends StatefulWidget {
  final AudioTransController ctrl;
  final Map<String, dynamic>? initial;
  const _AudioTransDialog({required this.ctrl, this.initial});

  @override
  State<_AudioTransDialog> createState() => _AudioTransDialogState();
}

class _AudioTransDialogState extends State<_AudioTransDialog> {
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _audioBitrateCtrl;
  late final TextEditingController _threadCountCtrl;

  static const List<String> _supportedAudioExts = [
    '.mp3',
    '.flac',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.wma',
    '.ape',
    '.m4a',
  ];

  String _format = 'mp3';
  String _sampleRate = 'source';
  String _channels = 'source';
  String _bitrateMode = 'auto';
  String _nonAudioPolicy = 'skip';
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
    final initNonAudio =
        (widget.initial?['non_audio_policy']?.toString() ?? 'skip')
            .trim()
            .toLowerCase();
    final cfg = _parseConfig(widget.initial?['trans_config']);

    _format = _normalizeIn(cfg['out_format']?.toString(), [
      'mp3',
      'm4a',
      'aac',
      'flac',
      'ogg',
      'wav',
      'opus',
      'wma',
    ], fallback: 'mp3');
    _sampleRate = _normalizeIn(cfg['sample_rate']?.toString(), [
      'source',
      '48000',
      '44100',
      '32000',
      '22050',
    ], fallback: 'source');
    _channels = _normalizeIn(cfg['channels']?.toString(), [
      'source',
      'stereo',
      'mono',
    ], fallback: 'source');

    final ab = num.tryParse(cfg['audio_bitrate_kbps']?.toString() ?? '');
    final threadRaw = int.tryParse(cfg['thread_count']?.toString() ?? '');
    final threadCount = (threadRaw ?? 5).clamp(1, 50);

    _bitrateMode = ab != null && ab > 0 ? 'custom' : 'auto';

    _sourceCtrl = TextEditingController(text: initSource);
    _targetCtrl = TextEditingController(text: initTarget);
    _audioBitrateCtrl = TextEditingController(
      text: ab == null ? '' : ab.toString(),
    );
    _threadCountCtrl = TextEditingController(text: threadCount.toString());

    _nonAudioPolicy = initNonAudio == 'copy' ? 'copy' : 'skip';
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    _audioBitrateCtrl.dispose();
    _threadCountCtrl.dispose();
    super.dispose();
  }

  String _normalizeIn(
    String? raw,
    List<String> options, {
    required String fallback,
  }) {
    final s = (raw ?? '').trim().toLowerCase();
    if (options.contains(s)) return s;
    return fallback;
  }

  Future<void> _pickSource() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: true,
      initialPath: _sourceCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    final picked = res.first.trim();
    if (picked.isEmpty) return;
    final ext = p.extension(picked).trim().toLowerCase();
    if (ext.isNotEmpty && !_supportedAudioExts.contains(ext)) {
      DialogUtil.showErrorDialog(
        message: '${'support_format'.tr}：${_supportedAudioExts.join(', ')}',
      );
      return;
    }
    _sourceCtrl.text = picked;
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

  num? _parseNullablePositiveNum(
    TextEditingController c, {
    required num min,
    required num max,
  }) {
    final raw = c.text.trim();
    if (raw.isEmpty) return null;
    final n = num.tryParse(raw);
    if (n == null) return null;
    if (n <= 0) return null;
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  Map<String, dynamic> _buildConfig() {
    final ab = _bitrateMode == 'custom'
        ? _parseNullablePositiveNum(_audioBitrateCtrl, min: 8, max: 2000)
        : null;
    final threadRaw = int.tryParse(_threadCountCtrl.text.trim());
    final threadCount = (threadRaw ?? 5).clamp(1, 50);
    _threadCountCtrl.text = threadCount.toString();

    return <String, dynamic>{
      'out_format': _format,
      'acodec': _codecForFormat(_format),
      'sample_rate': _sampleRate,
      'channels': _channels,
      'audio_bitrate_kbps': ab,
      'thread_count': threadCount,
    };
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = int.tryParse(widget.initial?['id']?.toString() ?? '');
    final source = _sourceCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    if (source.isEmpty || target.isEmpty) {
      DialogUtil.showErrorDialog(message: 'media_tool_audio_trans_required'.tr);
      return;
    }

    setState(() => _saving = true);
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final ok = await widget.ctrl.upsert(
        id: _isEdit ? id : null,
        sourcePath: source,
        targetPath: target,
        transConfig: _buildConfig(),
        nonAudioPolicy: _nonAudioPolicy,
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

  Widget _modeDropdown({
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return CustomDropdownField<String>(
      value: value,
      enabled: enabled,
      items: [
        DropdownMenuItem(value: 'auto', child: Text('auto'.tr)),
        DropdownMenuItem(value: 'custom', child: Text('media_tool_custom'.tr)),
      ],
      onChanged: (v) {
        final next = v?.toString() ?? '';
        if (next != 'auto' && next != 'custom') return;
        onChanged(next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = _isRunning || _saving;

    return WillPopScope(
      onWillPop: () async => !_saving,
      child: DialogUtil.createAlertDialog(
        title: Row(
          children: [
            Icon(Icons.audiotrack_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(_isEdit ? 'edit'.tr : 'create'.tr),
          ],
        ),
        constraints: const BoxConstraints(maxWidth: 620, minWidth: 360),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                _sectionHeader(
                  context,
                  'media_tool_audio_trans_section_paths'.tr,
                  Icons.folder_outlined,
                ),
                CustomTextField(
                  controller: _sourceCtrl,
                  labelText: 'media_tool_audio_trans_source'.tr,
                  hintText: 'media_tool_audio_trans_pick_source'.tr,
                  enabled: !disabled,
                  readOnly: true,
                  onTap: disabled ? null : _pickSource,
                  suffixIcon: const Icon(Icons.audio_file_outlined),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _targetCtrl,
                  labelText: 'media_tool_audio_trans_target'.tr,
                  hintText: 'media_tool_audio_trans_pick_target'.tr,
                  enabled: !disabled,
                  readOnly: true,
                  onTap: disabled ? null : _pickTarget,
                  suffixIcon: const Icon(Icons.folder_outlined),
                ),
                const SizedBox(height: 16),
                _sectionHeader(
                  context,
                  'media_tool_audio_trans_section_format'.tr,
                  Icons.tune_rounded,
                ),
                CustomDropdownField<String>(
                  value: _format,
                  labelText: 'media_tool_audio_trans_out_format'.tr,
                  enabled: !disabled,
                  items: const [
                    DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                    DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                    DropdownMenuItem(value: 'aac', child: Text('AAC')),
                    DropdownMenuItem(value: 'flac', child: Text('FLAC')),
                    DropdownMenuItem(value: 'ogg', child: Text('OGG')),
                    DropdownMenuItem(value: 'wav', child: Text('WAV')),
                    DropdownMenuItem(value: 'opus', child: Text('Opus')),
                    DropdownMenuItem(value: 'wma', child: Text('WMA')),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (![
                      'mp3',
                      'm4a',
                      'aac',
                      'flac',
                      'ogg',
                      'wav',
                      'opus',
                      'wma',
                    ].contains(next)) {
                      return;
                    }
                    setState(() => _format = next);
                  },
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _sampleRate,
                  labelText: 'media_tool_audio_trans_sample_rate'.tr,
                  enabled: !disabled,
                  items: [
                    DropdownMenuItem(
                      value: 'source',
                      child: Text('media_tool_audio_trans_sample_rate_source'.tr),
                    ),
                    const DropdownMenuItem(value: '48000', child: Text('48000 Hz')),
                    const DropdownMenuItem(value: '44100', child: Text('44100 Hz')),
                    const DropdownMenuItem(value: '32000', child: Text('32000 Hz')),
                    const DropdownMenuItem(value: '22050', child: Text('22050 Hz')),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (![
                      'source',
                      '48000',
                      '44100',
                      '32000',
                      '22050',
                    ].contains(next)) {
                      return;
                    }
                    setState(() => _sampleRate = next);
                  },
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _channels,
                  labelText: 'media_tool_audio_trans_channels'.tr,
                  enabled: !disabled,
                  items: [
                    DropdownMenuItem(
                      value: 'source',
                      child: Text('media_tool_audio_trans_channels_source'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'stereo',
                      child: Text('media_tool_audio_trans_channels_stereo'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'mono',
                      child: Text('media_tool_audio_trans_channels_mono'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (!['source', 'stereo', 'mono'].contains(next)) return;
                    setState(() => _channels = next);
                  },
                ),
                const SizedBox(height: 16),
                _sectionHeader(
                  context,
                  'media_tool_audio_trans_section_advanced'.tr,
                  Icons.settings_outlined,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('media_tool_audio_trans_audio_bitrate'.tr),
                          const SizedBox(height: 6),
                          _modeDropdown(
                            value: _bitrateMode,
                            enabled: !disabled,
                            onChanged: (v) => setState(() => _bitrateMode = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _audioBitrateCtrl,
                        labelText: 'media_tool_audio_trans_audio_bitrate_kbps'.tr,
                        enabled: !disabled && _bitrateMode == 'custom',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _threadCountCtrl,
                  labelText: 'media_tool_audio_trans_thread_count'.tr,
                  enabled: !disabled,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _nonAudioPolicy,
                  labelText: 'media_tool_audio_trans_non_audio'.tr,
                  enabled: !disabled,
                  items: [
                    DropdownMenuItem(value: 'skip', child: Text('skip'.tr)),
                    DropdownMenuItem(
                      value: 'copy',
                      child: Text('media_tool_audio_trans_non_audio_copy'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (next != 'skip' && next != 'copy') return;
                    setState(() => _nonAudioPolicy = next);
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
