part of '../file_share_server_view.dart';

class _ConfigDialogState extends State<_ConfigDialog> {
  int? _selectedUid;
  late final List<_RootPathRowState> _rows;

  @override
  void initState() {
    super.initState();
    final initialUid = int.tryParse(
      widget.initialItem?['uid']?.toString() ?? '',
    );
    _selectedUid = initialUid;
    _rows = _buildInitialRows(widget.initialItem?['root_path']);
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<_RootPathRowState> _buildInitialRows(dynamic rootPath) {
    final list = <_RootPathRowState>[];
    bool toBool(dynamic v, {bool defaultValue = true}) {
      if (v == null) return defaultValue;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final t = v.trim().toLowerCase();
        if (t == '1' || t == 'true') return true;
        if (t == '0' || t == 'false') return false;
        return defaultValue;
      }
      return defaultValue;
    }

    if (rootPath is List) {
      for (final it in rootPath) {
        if (it is String) {
          final path = it.trim();
          if (path.isEmpty) continue;
          list.add(_RootPathRowState(path: path));
          continue;
        }
        if (it is Map) {
          final path = it['path']?.toString().trim() ?? '';
          if (path.isEmpty) continue;
          list.add(
            _RootPathRowState(
              path: path,
              write: toBool(it['write'], defaultValue: true),
              update: toBool(it['update'], defaultValue: true),
              delete: toBool(it['delete'], defaultValue: true),
            ),
          );
          continue;
        }
      }
    }
    if (list.isEmpty) {
      list.add(_RootPathRowState(path: ''));
    }
    return list;
  }

  Future<int?> _pickUser(BuildContext context) async {
    return showDialog<int>(
      context: context,
      builder: (_) =>
          _UserPickerDialog(ctrl: widget.ctrl, selectedUid: _selectedUid),
    );
  }

  void _addRow() {
    setState(() => _rows.add(_RootPathRowState(path: '')));
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    _rows.removeAt(index);
    setState(() {});
  }

  Future<void> _pickPathForRow(int index) async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
    );
    final picked = (res ?? const []).isNotEmpty ? res!.first : null;
    if (picked == null || picked.trim().isEmpty) return;
    setState(() {
      _rows[index].path = picked.trim();
    });
  }

  Future<void> _submit() async {
    final uid = _selectedUid;
    if (uid == null) {
      DialogUtil.showErrorDialog(
        message: 'file_share_server_choose_user_hint'.tr,
      );
      return;
    }

    final initialUid = int.tryParse(
      widget.initialItem?['uid']?.toString() ?? '',
    );
    if (widget.existingUids
            .map((e) => e?.toString())
            .contains(uid.toString()) &&
        (initialUid == null || uid != initialUid)) {
      DialogUtil.showErrorDialog(
        message: 'file_share_server_user_duplicate'.tr,
      );
      return;
    }

    final out = <Map<String, dynamic>>[];
    final seenPaths = <String>{};
    for (final r in _rows) {
      final path = r.path.trim();
      if (path.isEmpty) continue;
      if (seenPaths.contains(path)) {
        DialogUtil.showErrorDialog(
          message: 'file_share_server_path_duplicate'.tr,
        );
        return;
      }
      seenPaths.add(path);
      out.add({
        'path': path,
        'write': r.write ? 1 : 0,
        'update': r.update ? 1 : 0,
        'delete': r.delete ? 1 : 0,
      });
    }

    if (out.isEmpty) {
      DialogUtil.showErrorDialog(
        message: 'file_share_server_no_path_selected'.tr,
      );
      return;
    }

    Navigator.of(context).pop(_ConfigDialogResult(uid: uid, rootPath: out));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.initialItem != null;

    final selectedUser = _selectedUid == null
        ? null
        : widget.ctrl.usersById[_selectedUid!];
    final selectedLabel = selectedUser == null
        ? 'file_share_server_choose_user_hint'.tr
        : (selectedUser['username']?.toString() ?? '');

    return DialogUtil.createAlertDialog(
      title: Text(
        editing
            ? 'file_share_server_edit_config'.tr
            : 'file_share_server_add_config'.tr,
      ),
      constraints: const BoxConstraints(maxWidth: 560, minWidth: 280),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final picked = await _pickUser(context);
                  if (picked == null) return;
                  setState(() => _selectedUid = picked);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right_outlined),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'file_share_server_paths'.tr,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add_outlined),
                    label: Text('file_share_server_add_path'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return _RootPathRow(
                      state: r,
                      onPickPath: () => _pickPathForRow(i),
                      onRemove: () => _removeRow(i),
                      canRemove: _rows.length > 1,
                      onChanged: () => setState(() {}),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(onPressed: _submit, child: Text('confirm'.tr)),
      ],
    );
  }
}
