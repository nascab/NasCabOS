part of '../video_trans_view.dart';

class _VideoTransDialog extends StatefulWidget {
  final VideoTransController ctrl;
  final Map<String, dynamic>? initial;
  const _VideoTransDialog({required this.ctrl, this.initial});

  @override
  State<_VideoTransDialog> createState() => _VideoTransDialogState();
}

class _VideoTransDialogState extends State<_VideoTransDialog> {
  late final TextEditingController _sourceCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _videoBitrateCtrl;
  late final TextEditingController _audioBitrateCtrl;
  late final TextEditingController _fpsCtrl;
  late final TextEditingController _threadCountCtrl;

  static const List<String> _supportedVideoExts = [
    '.mov',
    '.mp4',
    '.avi',
    '.rm',
    '.mkv',
    '.f4v',
    '.vob',
    '.mpg',
    '.rmvb',
    '.asf',
    '.mts',
    '.ts',
    '.wmv',
    '.m4v',
    '.m2ts',
    '.ogg',
    '.3gp',
    '.flv',
  ];

  String _format = 'mp4';
  String _vcodec = 'h264';
  String _acodec = 'aac';
  String _resolution = 'source';

  String _videoBitrateMode = 'auto';
  String _audioBitrateMode = 'auto';
  String _fpsMode = 'auto';

  String _nonVideoPolicy = 'skip';
  bool _enableHwAccel = true;

  bool _saving = false;

  bool get _isEdit => widget.initial != null;
  bool get _isRunning =>
      (widget.initial?['status']?.toString() ?? '').trim().toLowerCase() ==
      'running';
  bool get _isAnimated => _format == 'gif' || _format == 'webp';

  List<String> get _resolutionOptions {
    if (_isAnimated) {
      return const ['1080p', '720p', '480p', '320p', '240p'];
    }
    return const [
      'source',
      '8k',
      '4k',
      '1080p',
      '720p',
      '480p',
      '320p',
      '240p',
    ];
  }

  void _ensureResolutionValid() {
    if (_resolutionOptions.contains(_resolution)) return;
    _resolution = _isAnimated ? '480p' : 'source';
  }

  @override
  void initState() {
    super.initState();

    final initSource = widget.initial?['source_path']?.toString() ?? '';
    final initTarget = widget.initial?['target_path']?.toString() ?? '';
    final initNonVideo =
        (widget.initial?['non_video_policy']?.toString() ?? 'skip')
            .trim()
            .toLowerCase();
    final cfg = _parseConfig(widget.initial?['trans_config']);

    _format = _normalizeIn(cfg['out_format']?.toString(), [
      'mp4',
      'mov',
      'avi',
      'gif',
      'webp',
    ], fallback: 'mp4');
    _vcodec = _normalizeIn(cfg['vcodec']?.toString(), [
      'h264',
      'h265',
    ], fallback: 'h264');
    _acodec = _normalizeIn(cfg['acodec']?.toString(), [
      'aac',
      'mp3',
    ], fallback: 'aac');
    _resolution = _normalizeIn(cfg['resolution']?.toString(), [
      'source',
      '8k',
      '4k',
      '1080p',
      '720p',
      '480p',
      '320p',
      '240p',
    ], fallback: 'source');
    _ensureResolutionValid();

    final vb = num.tryParse(cfg['video_bitrate_mbps']?.toString() ?? '');
    final ab = num.tryParse(cfg['audio_bitrate_kbps']?.toString() ?? '');
    final fps = num.tryParse(cfg['fps']?.toString() ?? '');
    final threadRaw = int.tryParse(cfg['thread_count']?.toString() ?? '');
    final threadCount = (threadRaw ?? 5).clamp(1, 50);
    final enableHw = cfg['enable_hw_accel'];
    _enableHwAccel = enableHw is bool ? enableHw : true;

    _videoBitrateMode = vb != null && vb > 0 ? 'custom' : 'auto';
    _audioBitrateMode = ab != null && ab > 0 ? 'custom' : 'auto';
    _fpsMode = fps != null && fps > 0 ? 'custom' : 'auto';

    _sourceCtrl = TextEditingController(text: initSource);
    _targetCtrl = TextEditingController(text: initTarget);
    _videoBitrateCtrl = TextEditingController(
      text: vb == null ? '' : vb.toString(),
    );
    _audioBitrateCtrl = TextEditingController(
      text: ab == null ? '' : ab.toString(),
    );
    _fpsCtrl = TextEditingController(text: fps == null ? '' : fps.toString());
    _threadCountCtrl = TextEditingController(text: threadCount.toString());

    _nonVideoPolicy = initNonVideo == 'copy' ? 'copy' : 'skip';
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    _videoBitrateCtrl.dispose();
    _audioBitrateCtrl.dispose();
    _fpsCtrl.dispose();
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
    if (ext.isNotEmpty && !_supportedVideoExts.contains(ext)) {
      DialogUtil.showErrorDialog(
        message: '${'support_format'.tr}：${_supportedVideoExts.join(', ')}',
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
    final vb = !_isAnimated && _videoBitrateMode == 'custom'
        ? _parseNullablePositiveNum(_videoBitrateCtrl, min: 0.1, max: 500)
        : null;
    final ab = !_isAnimated && _audioBitrateMode == 'custom'
        ? _parseNullablePositiveNum(_audioBitrateCtrl, min: 8, max: 2000)
        : null;
    final fps = _fpsMode == 'custom'
        ? _parseNullablePositiveNum(
            _fpsCtrl,
            min: _isAnimated ? 5 : 20,
            max: _isAnimated ? 20 : 240,
          )
        : null;
    final threadRaw = int.tryParse(_threadCountCtrl.text.trim());
    final threadCount = (threadRaw ?? 5).clamp(1, 50);
    _threadCountCtrl.text = threadCount.toString();

    final m = <String, dynamic>{
      'out_format': _format,
      'vcodec': _vcodec,
      'acodec': _acodec,
      'resolution': _resolution,
      'video_bitrate_mbps': vb,
      'audio_bitrate_kbps': ab,
      'fps': fps,
      'thread_count': threadCount,
      'enable_hw_accel': _enableHwAccel,
    };
    return m;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = int.tryParse(widget.initial?['id']?.toString() ?? '');
    final source = _sourceCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    if (source.isEmpty || target.isEmpty) {
      DialogUtil.showErrorDialog(message: 'media_tool_video_trans_required'.tr);
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
        nonVideoPolicy: _nonVideoPolicy,
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
        title: Text(_isEdit ? 'edit'.tr : 'create'.tr),
        constraints: const BoxConstraints(maxWidth: 620, minWidth: 360),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 12),
                CustomTextField(
                  controller: _sourceCtrl,
                  labelText: 'media_tool_video_trans_source'.tr,
                  hintText: 'media_tool_video_trans_pick_source'.tr,
                  enabled: !disabled,
                  readOnly: true,
                  onTap: disabled ? null : _pickSource,
                  suffixIcon: const Icon(Icons.video_file_outlined),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _targetCtrl,
                  labelText: 'media_tool_video_trans_target'.tr,
                  hintText: 'media_tool_video_trans_pick_target'.tr,
                  enabled: !disabled,
                  readOnly: true,
                  onTap: disabled ? null : _pickTarget,
                  suffixIcon: const Icon(Icons.folder_outlined),
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _format,
                  labelText: 'media_tool_video_trans_out_format'.tr,
                  enabled: !disabled,
                  items: [
                    const DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                    const DropdownMenuItem(value: 'mov', child: Text('MOV')),
                    const DropdownMenuItem(value: 'avi', child: Text('AVI')),
                    DropdownMenuItem(
                      value: 'webp',
                      child: Text('media_tool_video_trans_out_format_webp'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'gif',
                      child: Text('media_tool_video_trans_out_format_gif'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (!['mp4', 'mov', 'avi', 'gif', 'webp'].contains(next)) {
                      return;
                    }
                    setState(() {
                      _format = next;
                      _ensureResolutionValid();
                      if (_isAnimated) {
                        _videoBitrateMode = 'auto';
                        _audioBitrateMode = 'auto';
                        _videoBitrateCtrl.clear();
                        _audioBitrateCtrl.clear();
                      }
                    });
                  },
                ),
                if (_isAnimated) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'media_tool_video_trans_animated_hint'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!_isAnimated) ...[
                  CustomDropdownField<String>(
                    value: _vcodec,
                    labelText: 'media_tool_video_trans_video_codec'.tr,
                    enabled: !disabled,
                    items: const [
                      DropdownMenuItem(value: 'h264', child: Text('H.264')),
                      DropdownMenuItem(value: 'h265', child: Text('H.265')),
                    ],
                    onChanged: (v) {
                      final next = (v?.toString() ?? '').toLowerCase();
                      if (next != 'h264' && next != 'h265') return;
                      setState(() => _vcodec = next);
                    },
                  ),
                  const SizedBox(height: 12),
                  CustomDropdownField<String>(
                    value: _acodec,
                    labelText: 'media_tool_video_trans_audio_format'.tr,
                    enabled: !disabled,
                    items: const [
                      DropdownMenuItem(value: 'aac', child: Text('AAC')),
                      DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                    ],
                    onChanged: (v) {
                      final next = (v?.toString() ?? '').toLowerCase();
                      if (next != 'aac' && next != 'mp3') return;
                      setState(() => _acodec = next);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                CustomDropdownField<String>(
                  value: _resolution,
                  labelText: 'media_tool_video_trans_resolution'.tr,
                  enabled: !disabled,
                  items: _resolutionOptions.map((v) {
                    switch (v) {
                      case 'source':
                        return DropdownMenuItem(
                          value: 'source',
                          child: Text(
                            'media_tool_video_trans_resolution_source'.tr,
                          ),
                        );
                      case '8k':
                        return DropdownMenuItem(
                          value: '8k',
                          child: Text(
                            'media_tool_video_trans_resolution_8k'.tr,
                          ),
                        );
                      case '4k':
                        return DropdownMenuItem(
                          value: '4k',
                          child: Text(
                            'media_tool_video_trans_resolution_4k'.tr,
                          ),
                        );
                      case '1080p':
                        return DropdownMenuItem(
                          value: '1080p',
                          child: Text(
                            'media_tool_video_trans_resolution_1080p'.tr,
                          ),
                        );
                      case '720p':
                        return DropdownMenuItem(
                          value: '720p',
                          child: Text(
                            'media_tool_video_trans_resolution_720p'.tr,
                          ),
                        );
                      case '480p':
                        return DropdownMenuItem(
                          value: '480p',
                          child: Text(
                            'media_tool_video_trans_resolution_480p'.tr,
                          ),
                        );
                      case '320p':
                        return DropdownMenuItem(
                          value: '320p',
                          child: Text(
                            'media_tool_video_trans_resolution_320p'.tr,
                          ),
                        );
                      case '240p':
                        return DropdownMenuItem(
                          value: '240p',
                          child: Text(
                            'media_tool_video_trans_resolution_240p'.tr,
                          ),
                        );
                      default:
                        return DropdownMenuItem(value: v, child: Text(v));
                    }
                  }).toList(),
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (!_resolutionOptions.contains(next)) {
                      return;
                    }
                    setState(() => _resolution = next);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('media_tool_video_trans_enable_hw_accel'.tr),
                    ),
                    CustomSwitch(
                      value: _enableHwAccel,
                      onChanged: disabled
                          ? null
                          : (v) {
                              setState(() => _enableHwAccel = v);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _threadCountCtrl,
                  labelText: 'media_tool_video_trans_thread_count'.tr,
                  enabled: !disabled,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                if (!_isAnimated) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('media_tool_video_trans_video_bitrate'.tr),
                            const SizedBox(height: 6),
                            _modeDropdown(
                              value: _videoBitrateMode,
                              enabled: !disabled,
                              onChanged: (v) =>
                                  setState(() => _videoBitrateMode = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          controller: _videoBitrateCtrl,
                          labelText:
                              'media_tool_video_trans_video_bitrate_mbps'.tr,
                          enabled: !disabled && _videoBitrateMode == 'custom',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('media_tool_video_trans_audio_bitrate'.tr),
                            const SizedBox(height: 6),
                            _modeDropdown(
                              value: _audioBitrateMode,
                              enabled: !disabled,
                              onChanged: (v) =>
                                  setState(() => _audioBitrateMode = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          controller: _audioBitrateCtrl,
                          labelText:
                              'media_tool_video_trans_audio_bitrate_kbps'.tr,
                          enabled: !disabled && _audioBitrateMode == 'custom',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('media_tool_video_trans_fps'.tr),
                          const SizedBox(height: 6),
                          _modeDropdown(
                            value: _fpsMode,
                            enabled: !disabled,
                            onChanged: (v) => setState(() => _fpsMode = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _fpsCtrl,
                        labelText:
                            (_isAnimated
                                    ? 'media_tool_video_trans_fps_value_animated'
                                    : 'media_tool_video_trans_fps_value')
                                .tr,
                        enabled: !disabled && _fpsMode == 'custom',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _nonVideoPolicy,
                  labelText: 'media_tool_video_trans_non_video'.tr,
                  enabled: !disabled,
                  items: [
                    DropdownMenuItem(value: 'skip', child: Text('skip'.tr)),
                    DropdownMenuItem(
                      value: 'copy',
                      child: Text('media_tool_video_trans_non_video_copy'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = (v?.toString() ?? '').toLowerCase();
                    if (next != 'skip' && next != 'copy') return;
                    setState(() => _nonVideoPolicy = next);
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
