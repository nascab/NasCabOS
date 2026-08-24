part of '../file_mount_view.dart';

class _MountDialog extends StatefulWidget {
  final FileMountController ctrl;
  final Map<String, dynamic>? initial;
  const _MountDialog({required this.ctrl, this.initial});

  @override
  State<_MountDialog> createState() => _MountDialogState();
}

class _MountDialogState extends State<_MountDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mountPathCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _remotePathCtrl;

  String _protocol = 'webdav';
  String _webdavScheme = 'http';

  /// 与 rclone --webdav-vendor 一致；选错时部分服务端会列目录为空
  String _webdavVendor = 'other';

  /// 默认跳过 HTTPS 证书校验；仅当配置显式为 false 时关闭
  bool _webdavSkipTlsVerify = true;
  bool _webdavTrailingSlash = false;
  bool _showPassword = false;
  bool _saving = false;

  bool get _isEdit => widget.initial != null;
  bool get _isRunning =>
      (widget.initial?['status']?.toString() ?? '').trim().toLowerCase() ==
      'running';

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? const {};
    _nameCtrl = TextEditingController(text: init['name']?.toString() ?? '');
    _mountPathCtrl = TextEditingController(
      text: init['mount_path']?.toString() ?? '',
    );
    final cfg = init['config'];
    final cfgMap = cfg is Map
        ? cfg.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final protocol = (cfgMap['protocol']?.toString() ?? '')
        .trim()
        .toLowerCase();
    if (protocol == 'webdav' || protocol == 'ftp' || protocol == 'sftp') {
      _protocol = protocol;
    }
    final scheme = (cfgMap['scheme']?.toString() ?? '').trim().toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      _webdavScheme = scheme;
    }
    const webdavVendors = <String>{
      'fastmail',
      'nextcloud',
      'owncloud',
      'infinitescale',
      'sharepoint',
      'sharepoint-ntlm',
      'rclone',
      'other',
    };
    final v = (cfgMap['vendor']?.toString() ?? '').trim().toLowerCase();
    if (webdavVendors.contains(v)) {
      _webdavVendor = v;
    }
    _webdavSkipTlsVerify = cfgMap['webdav_skip_verify'] != false;
    if (cfgMap['webdav_trailing_slash'] == true) {
      _webdavTrailingSlash = true;
    }
    _hostCtrl = TextEditingController(text: cfgMap['host']?.toString() ?? '');
    _portCtrl = TextEditingController(text: cfgMap['port']?.toString() ?? '');
    _usernameCtrl = TextEditingController(
      text: cfgMap['username']?.toString() ?? '',
    );
    _passwordCtrl = TextEditingController(text: '');
    _remotePathCtrl = TextEditingController(
      text: cfgMap['remote_path']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mountPathCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _remotePathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMountPath() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _mountPathCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    _mountPathCtrl.text = res.first;
  }

  int? _parsePort(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v <= 0 || v > 65535) return null;
    return v;
  }

  bool _isValidMountFolderName(String value) {
    final t = value.trim();
    if (t.isEmpty) return false;
    if (t == '.' || t == '..') return false;
    if (t.contains('/') || t.contains('\\')) return false;
    if (RegExp(r'[\x00-\x1F]').hasMatch(t)) return false;
    if (t.endsWith(' ') || t.endsWith('.')) return false;
    if (RegExp(r'[<>:"|?*]').hasMatch(t)) return false;
    return true;
  }

  int _defaultPort() {
    if (_protocol == 'sftp') return 22;
    if (_protocol == 'ftp') return 21;
    if (_protocol == 'webdav') return _webdavScheme == 'https' ? 443 : 80;
    return 0;
  }

  String _normalizePath(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '/';
    if (t.startsWith('/')) return t;
    return '/$t';
  }

  String _buildRemoteDisplay({
    required String protocol,
    required String scheme,
    required String host,
    required int port,
    required String remotePath,
  }) {
    final path = _normalizePath(remotePath);
    if (protocol == 'webdav') {
      return '$scheme://$host:$port$path';
    }
    return '$protocol://$host:$port$path';
  }

  Future<void> _submit() async {
    if (_saving) return;
    final id = int.tryParse(widget.initial?['id']?.toString() ?? '');
    final name = _nameCtrl.text.trim();
    final mountPath = _mountPathCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final portParsed = _parsePort(_portCtrl.text);
    final port = portParsed ?? _defaultPort();
    final remotePath = _remotePathCtrl.text.trim();

    if (name.isEmpty ||
        mountPath.isEmpty ||
        host.isEmpty ||
        username.isEmpty ||
        (!_isEdit && password.trim().isEmpty)) {
      DialogUtil.showErrorDialog(message: 'file_mount_required'.tr);
      return;
    }
    if (!_isValidMountFolderName(name)) {
      DialogUtil.showErrorDialog(message: 'file_mount_name_invalid'.tr);
      return;
    }
    if (port <= 0) {
      DialogUtil.showErrorDialog(message: 'file_share_server_port_invalid'.tr);
      return;
    }

    final cfg = <String, dynamic>{
      'protocol': _protocol,
      'host': host,
      'port': port,
      'username': username,
      'remote_path': _normalizePath(remotePath),
      if (_protocol == 'webdav') 'scheme': _webdavScheme,
      if (_protocol == 'webdav') 'vendor': _webdavVendor,
      if (_protocol == 'webdav') 'webdav_skip_verify': _webdavSkipTlsVerify,
      if (_protocol == 'webdav') 'webdav_trailing_slash': _webdavTrailingSlash,
      if (password.trim().isNotEmpty) 'password': password.trim(),
    };
    final remote = _buildRemoteDisplay(
      protocol: _protocol,
      scheme: _webdavScheme,
      host: host,
      port: port,
      remotePath: remotePath,
    );

    setState(() => _saving = true);
    DialogUtil.showLoading(message: 'loading'.tr);
    try {
      final ok = await widget.ctrl.upsert(
        id: _isEdit ? id : null,
        name: name,
        mountPath: mountPath,
        remote: remote,
        config: cfg,
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
        title: Text(_isEdit ? 'file_mount_edit'.tr : 'file_mount_create'.tr),
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                CustomTextField(
                  controller: _nameCtrl,
                  labelText: 'file_mount_name'.tr,
                  hintText: 'input_please'.tr,
                  enabled: !_isRunning && !_saving,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _mountPathCtrl,
                  labelText: 'file_mount_mount_path'.tr,
                  hintText: 'input_please'.tr,
                  enabled: !_isRunning && !_saving,
                  readOnly: true,
                  onTap: _isRunning || _saving ? null : _pickMountPath,
                ),
                const SizedBox(height: 12),
                CustomDropdownField<String>(
                  value: _protocol,
                  labelText: 'file_mount_protocol'.tr,
                  enabled: !_isRunning && !_saving,
                  items: [
                    DropdownMenuItem(
                      value: 'webdav',
                      child: Text('file_share_server_webdav'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'ftp',
                      child: Text('file_share_server_ftp'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'sftp',
                      child: Text('file_share_server_sftp'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    final next = v?.toString() ?? '';
                    if (next != 'webdav' && next != 'ftp' && next != 'sftp') {
                      return;
                    }
                    setState(() => _protocol = next);
                  },
                ),
                if (_protocol == 'webdav') ...[
                  const SizedBox(height: 12),
                  CustomDropdownField<String>(
                    value: _webdavScheme,
                    labelText: 'file_mount_webdav_scheme'.tr,
                    enabled: !_isRunning && !_saving,
                    items: const [
                      DropdownMenuItem(value: 'http', child: Text('http')),
                      DropdownMenuItem(value: 'https', child: Text('https')),
                    ],
                    onChanged: (v) {
                      final next = v?.toString() ?? '';
                      if (next != 'http' && next != 'https') return;
                      setState(() => _webdavScheme = next);
                    },
                  ),
                  const SizedBox(height: 12),
                  CustomDropdownField<String>(
                    value: _webdavVendor,
                    labelText: 'file_mount_webdav_vendor'.tr,
                    enabled: !_isRunning && !_saving,
                    items: const [
                      DropdownMenuItem(value: 'other', child: Text('other')),
                      DropdownMenuItem(
                        value: 'nextcloud',
                        child: Text('nextcloud'),
                      ),
                      DropdownMenuItem(
                        value: 'owncloud',
                        child: Text('owncloud'),
                      ),
                      DropdownMenuItem(
                        value: 'infinitescale',
                        child: Text('infinitescale'),
                      ),
                      DropdownMenuItem(
                        value: 'sharepoint',
                        child: Text('sharepoint'),
                      ),
                      DropdownMenuItem(
                        value: 'sharepoint-ntlm',
                        child: Text('sharepoint-ntlm'),
                      ),
                      DropdownMenuItem(
                        value: 'fastmail',
                        child: Text('fastmail'),
                      ),
                      DropdownMenuItem(value: 'rclone', child: Text('rclone')),
                    ],
                    onChanged: (v) {
                      final next = v?.toString() ?? '';
                      const allowed = {
                        'other',
                        'nextcloud',
                        'owncloud',
                        'infinitescale',
                        'sharepoint',
                        'sharepoint-ntlm',
                        'fastmail',
                        'rclone',
                      };
                      if (!allowed.contains(next)) return;
                      setState(() => _webdavVendor = next);
                    },
                  ),
                  const SizedBox(height: 4),
                  if (_webdavScheme == 'https')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'file_mount_webdav_skip_tls'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: _webdavSkipTlsVerify,
                      onChanged: _isRunning || _saving
                          ? null
                          : (v) => setState(
                              () => _webdavSkipTlsVerify = v ?? false,
                            ),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'file_mount_webdav_trailing_slash'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    value: _webdavTrailingSlash,
                    onChanged: _isRunning || _saving
                        ? null
                        : (v) =>
                              setState(() => _webdavTrailingSlash = v ?? false),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _hostCtrl,
                        labelText: 'file_mount_server_host'.tr,
                        hintText: 'input_please'.tr,
                        enabled: !_isRunning && !_saving,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: CustomTextField(
                        controller: _portCtrl,
                        labelText: 'file_mount_server_port'.tr,
                        hintText: _defaultPort().toString(),
                        keyboardType: TextInputType.number,
                        enabled: !_isRunning && !_saving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _usernameCtrl,
                  labelText: 'username'.tr,
                  hintText: 'input_please'.tr,
                  enabled: !_isRunning && !_saving,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _passwordCtrl,
                  labelText: 'password'.tr,
                  hintText: _isEdit
                      ? 'file_mount_password_keep_tip'.tr
                      : 'input_please'.tr,
                  obscureText: !_showPassword,
                  enabled: !_isRunning && !_saving,
                  suffixIcon: IconButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _remotePathCtrl,
                  labelText: 'file_mount_remote_path'.tr,
                  hintText: '/',
                  enabled: !_isRunning && !_saving,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: _isRunning || _saving ? null : _submit,
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
  }
}
