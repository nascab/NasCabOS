part of '../file_mount_view.dart';

class _OpenlistMountDialog extends StatefulWidget {
  final OpenlistMountController ctrl;
  final Map<String, dynamic>? initial;
  const _OpenlistMountDialog({required this.ctrl, this.initial});

  @override
  State<_OpenlistMountDialog> createState() => _OpenlistMountDialogState();
}

class _OpenlistMountDialogState extends State<_OpenlistMountDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mountPathCtrl;
  final Map<String, TextEditingController> _fieldCtrls = {};
  final Map<String, bool> _boolFields = {};

  String _driver = '';
  bool _saving = false;
  List<Map<String, dynamic>> _driverFields = [];

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
    _driver = init['driver']?.toString() ?? '';
    widget.ctrl.loadDrivers().then((_) {
      if (_driver.isEmpty && widget.ctrl.drivers.isNotEmpty) {
        setState(() {
          _driver = _pickDriverName(widget.ctrl.drivers.first);
          _applyDriverFields(_driver);
        });
      } else if (_driver.isNotEmpty) {
        _applyDriverFields(_driver);
      }
      _loadInitialAddition(init);
    });
  }

  void _loadInitialAddition(Map<String, dynamic> init) {
    final cfg = init['config'];
    Map<String, dynamic>? addition;
    if (cfg is Map) {
      final add = cfg['addition'];
      if (add is Map) {
        addition = add.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    if (addition == null) return;
    for (final e in addition.entries) {
      final key = e.key;
      final val = e.value;
      if (_boolFields.containsKey(key)) {
        _boolFields[key] = val == true;
      } else if (_fieldCtrls.containsKey(key)) {
        _fieldCtrls[key]!.text = val?.toString() ?? '';
      }
    }
    if (mounted) setState(() {});
  }

  String _pickDriverName(Map<String, dynamic> d) {
    return (d['driver'] ?? d['name'] ?? '').toString();
  }

  List<Map<String, dynamic>> _parseAdditional(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is List) {
          return v
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  void _applyDriverFields(String driverName) {
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    _fieldCtrls.clear();
    _boolFields.clear();
    _driverFields = [];

    Map<String, dynamic>? found;
    for (final d in widget.ctrl.drivers) {
      if (_pickDriverName(d) == driverName) {
        found = d;
        break;
      }
    }
    if (found == null) return;

    _driverFields = _parseAdditional(found['additional']).where((f) {
      final name = (f['name'] ?? '').toString();
      if (name == 'client_id' ||
          name == 'client_secret' ||
          name == 'redirect_uri' ||
          name == 'use_online_api' ||
          name == 'api_url_address') {
        return false;
      }
      return true;
    }).toList();
    for (final f in _driverFields) {
      final name = (f['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final type = (f['type'] ?? 'string').toString().toLowerCase();
      if (type == 'bool') {
        _boolFields[name] = f['default'] == true;
      } else {
        final def = f['default']?.toString() ?? '';
        _fieldCtrls[name] = TextEditingController(text: def);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mountPathCtrl.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
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
    setState(() {});
  }

  Future<void> _openOAuthHelp() async {
    final url = Uri.tryParse(OpenlistDriverI18n.oauthUrlForDriver(_driver));
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  bool get _usesOnlineAuth => OpenlistDriverI18n.usesOnlineAuth(_driver);

  String? _driverDocUrlFor(String driver) {
    if (driver.isEmpty) return null;
    for (final d in widget.ctrl.drivers) {
      if (_pickDriverName(d) == driver) {
        final fromApi = d['docUrl']?.toString().trim();
        if (fromApi != null && fromApi.isNotEmpty) return fromApi;
        break;
      }
    }
    return OpenlistDriverI18n.driverDocUrl(driver);
  }

  Future<void> _openDriverDoc() async {
    final url = Uri.tryParse(_driverDocUrlFor(_driver) ?? '');
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Map<String, dynamic> _collectAddition() {
    final out = <String, dynamic>{};
    for (final e in _fieldCtrls.entries) {
      final v = e.value.text.trim();
      if (v.isNotEmpty) out[e.key] = v;
    }
    for (final e in _boolFields.entries) {
      out[e.key] = e.value;
    }
    return out;
  }

  bool _validateDriverFields() {
    for (final f in _driverFields) {
      final name = (f['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final required = f['required'] == true;
      final help = (f['help'] ?? '').toString().toLowerCase();
      final oneOf = help.contains('one of') && help.contains('required');
      if (!required && !oneOf) continue;

      final type = (f['type'] ?? 'string').toString().toLowerCase();
      if (type == 'bool') continue;

      final value = _fieldCtrls[name]?.text.trim() ?? '';
      if (value.isEmpty) {
        final label = OpenlistDriverI18n.fieldLabel(f);
        ToastUtil.show(
          'openlist_mount_field_required'.trParams({'field': label}),
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (_saving || _isRunning) return;
    final name = _nameCtrl.text.trim();
    final mountPath = _mountPathCtrl.text.trim();
    final driver = _driver.trim();
    if (name.isEmpty || mountPath.isEmpty || driver.isEmpty) {
      ToastUtil.show('openlist_mount_required'.tr);
      return;
    }
    if (!_validateDriverFields()) return;

    setState(() => _saving = true);
    final idRaw = widget.initial?['id'];
    final id = idRaw == null ? null : int.tryParse(idRaw.toString());
    final ok = await widget.ctrl.upsert(
      id: id,
      name: name,
      mountPath: mountPath,
      driver: driver,
      addition: _collectAddition(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Widget _buildDriverField(Map<String, dynamic> f) {
    final name = (f['name'] ?? '').toString();
    if (name.isEmpty) return const SizedBox.shrink();
    final label = OpenlistDriverI18n.fieldLabel(f);
    final hint = (f['help'] ?? '').toString().trim();
    final type = (f['type'] ?? 'string').toString().toLowerCase();
    final disabled = _isRunning;

    if (type == 'bool') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: hint.isNotEmpty && hint != label
            ? Text(hint, style: Theme.of(context).textTheme.bodySmall)
            : null,
        value: _boolFields[name] ?? false,
        onChanged: disabled
            ? null
            : (v) => setState(() => _boolFields[name] = v ?? false),
      );
    }

    if (type == 'select') {
      final optionsRaw = f['options'];
      final options = <String>[];
      if (optionsRaw is String && optionsRaw.trim().isNotEmpty) {
        options.addAll(
          optionsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
        );
      } else if (optionsRaw is List) {
        for (final o in optionsRaw) {
          if (o is Map && o['value'] != null) {
            options.add(o['value'].toString());
          } else {
            options.add(o.toString());
          }
        }
      }
      final current = _fieldCtrls[name]?.text ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CustomDropdownField<String>(
          labelText: label,
          value: options.contains(current)
              ? current
              : (options.isNotEmpty ? options.first : null),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: disabled
              ? null
              : (v) {
                  if (v == null) return;
                  _fieldCtrls[name]?.text = v;
                  setState(() {});
                },
        ),
      );
    }

    final isSecret =
        name.toLowerCase().contains('token') ||
        name.toLowerCase().contains('password') ||
        name.toLowerCase().contains('secret') ||
        name.toLowerCase().contains('cookie');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomTextField(
        controller: _fieldCtrls[name],
        labelText: label,
        hintText: hint.isNotEmpty && hint != label ? hint : null,
        enabled: !disabled,
        obscureText: isSecret,
        maxLines: isSecret ? 1 : (type == 'text' ? 3 : 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverItems = widget.ctrl.drivers
        .map((d) => _pickDriverName(d))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return DialogUtil.createAlertDialog(
      title: Text(
        _isEdit ? 'openlist_mount_edit'.tr : 'openlist_mount_create'.tr,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              CustomTextField(
                controller: _nameCtrl,
                labelText: 'file_mount_name'.tr,
                enabled: !_isRunning,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _mountPathCtrl,
                labelText: 'file_mount_mount_path'.tr,
                hintText: 'openlist_mount_pick_folder'.tr,
                enabled: !_isRunning,
                readOnly: true,
                onTap: _isRunning ? null : _pickMountPath,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: _isRunning ? null : _pickMountPath,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.ctrl.isDriversLoading.value)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                CustomDropdownField<String>(
                  labelText: 'openlist_mount_driver'.tr,
                  value: _driver.isNotEmpty && driverItems.contains(_driver)
                      ? _driver
                      : null,
                  items: driverItems
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(OpenlistDriverI18n.driverName(d)),
                        ),
                      )
                      .toList(),
                  onChanged: _isRunning
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _driver = v;
                            _applyDriverFields(v);
                          });
                        },
                ),
              const SizedBox(height: 8),
              if (_driver.isNotEmpty && _usesOnlineAuth)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'openlist_mount_oauth_hint'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (_driver.isNotEmpty && _driverDocUrlFor(_driver) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'openlist_mount_driver_doc_hint'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_usesOnlineAuth)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _driver.isEmpty ? null : _openOAuthHelp,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text('openlist_mount_oauth_help'.tr),
                  ),
                ),
              if (_driverDocUrlFor(_driver) != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _driver.isEmpty ? null : _openDriverDoc,
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: Text('openlist_mount_driver_doc_help'.tr),
                  ),
                ),
              if (_driverFields.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'openlist_mount_driver_config'.tr,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ..._driverFields.map(_buildDriverField),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: _saving || _isRunning ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('ok'.tr),
        ),
      ],
    );
  }
}
