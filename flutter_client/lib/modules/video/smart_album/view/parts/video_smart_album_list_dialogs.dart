part of '../video_smart_album_list_view.dart';

const Duration _smartAlbumDialogDisposeDelay = Duration(milliseconds: 350);

enum _ConditionFieldType { text, number }

class _ConditionFieldMeta {
  final String field;
  final _ConditionFieldType type;
  const _ConditionFieldMeta(this.field, this.type);

  bool get valid => field.trim().isNotEmpty;
}

_ConditionFieldMeta _conditionFieldMeta(String field) {
  switch (field.trim()) {
    case 'name':
      return const _ConditionFieldMeta('name', _ConditionFieldType.text);
    // case 'nfo_name':
    //   return const _ConditionFieldMeta('nfo_name', _ConditionFieldType.text);
    case 'nfo_actor':
      return const _ConditionFieldMeta('nfo_actor', _ConditionFieldType.text);
    case 'nfo_director':
      return const _ConditionFieldMeta(
        'nfo_director',
        _ConditionFieldType.text,
      );
    case 'nfo_genres':
      return const _ConditionFieldMeta('nfo_genres', _ConditionFieldType.text);
    case 'nfo_regions':
      return const _ConditionFieldMeta('nfo_regions', _ConditionFieldType.text);
    // case 'filename':
    //   return const _ConditionFieldMeta('filename', _ConditionFieldType.text);
    case 'path':
      return const _ConditionFieldMeta('path', _ConditionFieldType.text);
    case 'year':
      return const _ConditionFieldMeta('year', _ConditionFieldType.number);
    case 'score':
      return const _ConditionFieldMeta('score', _ConditionFieldType.number);
    case 'duration_min':
      return const _ConditionFieldMeta(
        'duration_min',
        _ConditionFieldType.number,
      );
    default:
      return const _ConditionFieldMeta('', _ConditionFieldType.text);
  }
}

String _fieldLabelKey(String field) {
  switch (field.trim()) {
    case 'name':
      return 'smart_album_field_name';
    // case 'nfo_name':
    //   return 'smart_album_field_nfo_name';
    case 'nfo_actor':
      return 'smart_album_field_nfo_actor';
    case 'nfo_director':
      return 'smart_album_field_nfo_director';
    case 'nfo_genres':
      return 'smart_album_field_nfo_genres';
    case 'nfo_regions':
      return 'smart_album_field_nfo_regions';
    case 'path':
      return 'path';
    case 'year':
      return 'smart_album_field_year';
    case 'score':
      return 'smart_album_field_score';
    case 'duration_min':
      return 'smart_album_field_duration';
    default:
      return field.trim();
  }
}

class _SmartConditionItem {
  String field;
  String operator;
  final TextEditingController valueCtrl;

  _SmartConditionItem({
    required this.field,
    required this.operator,
    TextEditingController? valueCtrl,
  }) : valueCtrl = valueCtrl ?? TextEditingController();

  factory _SmartConditionItem.empty() {
    return _SmartConditionItem(field: 'name', operator: 'contains');
  }

  void dispose() {
    valueCtrl.dispose();
  }
}

String _parseConditionLogic(Map<String, dynamic> filterContent) {
  final v = filterContent['logic']?.toString().toLowerCase();
  if (v == 'or') return 'or';
  return 'and';
}

List<_SmartConditionItem> _parseConditionItems(
  Map<String, dynamic> filterContent,
) {
  final raw = filterContent['conditions'];
  if (raw is! List) return <_SmartConditionItem>[];
  final items = <_SmartConditionItem>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = e.cast<String, dynamic>();
    final field = (m['field'] ?? '').toString();
    final meta = _conditionFieldMeta(field);
    if (!meta.valid) continue;
    final op = (m['operator'] ?? '').toString();
    final value = m['value'];
    if (meta.type == _ConditionFieldType.text) {
      if (op != 'contains') continue;
      final s = value?.toString() ?? '';
      final item = _SmartConditionItem(field: field, operator: 'contains');
      item.valueCtrl.text = s;
      items.add(item);
      continue;
    }
    if (meta.type == _ConditionFieldType.number) {
      if (op != 'gt' && op != 'eq' && op != 'lt') continue;
      final item = _SmartConditionItem(field: field, operator: op);
      item.valueCtrl.text = value?.toString() ?? '';
      items.add(item);
    }
  }
  return items;
}

Map<String, dynamic>? _buildFilterContent({
  required String conditionLogic,
  required List<_SmartConditionItem> conditionItems,
}) {
  final mapped = <Map<String, dynamic>>[];
  for (final item in conditionItems) {
    final meta = _conditionFieldMeta(item.field);
    if (!meta.valid) continue;
    if (meta.type == _ConditionFieldType.text) {
      final v = item.valueCtrl.text.trim();
      if (v.isEmpty) continue;
      mapped.add({'field': item.field, 'operator': 'contains', 'value': v});
      continue;
    }
    if (meta.type == _ConditionFieldType.number) {
      final n = num.tryParse(item.valueCtrl.text.trim());
      if (n == null) continue;
      final op = item.operator;
      if (op != 'gt' && op != 'eq' && op != 'lt') continue;
      mapped.add({'field': item.field, 'operator': op, 'value': n});
    }
  }

  if (mapped.isEmpty) return null;
  final logic = conditionLogic.toLowerCase() == 'or' ? 'or' : 'and';
  return {'logic': logic, 'conditions': mapped};
}

Widget _buildConditionEditor({
  required BuildContext context,
  required String logic,
  required ValueChanged<String> onLogicChanged,
  required List<_SmartConditionItem> items,
  required VoidCallback onAdd,
  required ValueChanged<int> onRemove,
}) {
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: logic,
              decoration: InputDecoration(
                labelText: 'smart_album_condition_relation'.tr,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'and',
                  child: Text('smart_album_condition_relation_and'.tr),
                ),
                DropdownMenuItem(
                  value: 'or',
                  child: Text('smart_album_condition_relation_or'.tr),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                onLogicChanged(v);
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 45.0,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text('smart_album_add_condition'.tr),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int idx = 0; idx < items.length; idx++) ...[
                _buildConditionRow(
                  context: context,
                  item: items[idx],
                  borderColor: theme.dividerColor,
                  onRemove: () => onRemove(idx),
                  onChanged: () => onLogicChanged(logic),
                ),
                if (idx != items.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

Widget _buildConditionRow({
  required BuildContext context,
  required _SmartConditionItem item,
  required Color borderColor,
  required VoidCallback onRemove,
  required VoidCallback onChanged,
}) {
  final meta = _conditionFieldMeta(item.field);
  final isText = meta.type == _ConditionFieldType.text;
  final isNumber = meta.type == _ConditionFieldType.number;
  const fields = <String>[
    'name',
    // 'nfo_name',
    'nfo_actor',
    'nfo_director',
    'nfo_genres',
    'nfo_regions',
    // 'filename',
    'path',
    'year',
    'score',
    'duration_min',
  ];

  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: item.field,
                decoration: InputDecoration(
                  labelText: 'smart_album_condition_field'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final f in fields)
                    DropdownMenuItem(
                      value: f,
                      child: Text(_fieldLabelKey(f).tr),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  item.field = v;
                  final meta = _conditionFieldMeta(v);
                  if (meta.type == _ConditionFieldType.text) {
                    item.operator = 'contains';
                  } else {
                    item.operator =
                        item.operator == 'gt' ||
                            item.operator == 'eq' ||
                            item.operator == 'lt'
                        ? item.operator
                        : 'gt';
                  }
                  item.valueCtrl.text = '';
                  onChanged();
                },
                selectedItemBuilder: (context) {
                  return [
                    for (final f in fields)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_fieldLabelKey(f).tr),
                      ),
                  ];
                },
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'delete'.tr,
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (isText)
          TextField(
            controller: item.valueCtrl,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'smart_album_operator_contains'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        if (isNumber)
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: item.operator,
                  decoration: InputDecoration(
                    labelText: 'smart_album_operator_compare'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'gt',
                      child: Text('smart_album_cmp_gt'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'eq',
                      child: Text('smart_album_cmp_eq'.tr),
                    ),
                    DropdownMenuItem(
                      value: 'lt',
                      child: Text('smart_album_cmp_lt'.tr),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    item.operator = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.valueCtrl,
                  onChanged: (_) => onChanged(),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: false,
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'smart_album_value'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

Future<void> _showCreateDialog(
  BuildContext context,
  VideoSmartAlbumController controller,
) async {
  var name = '';
  var conditionLogic = 'and';
  final conditionItems = <_SmartConditionItem>[_SmartConditionItem.empty()];

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final nav = Navigator.of(dialogContext);

            void closeDialog() {
              nav.pop();
            }

          final filterContent = _buildFilterContent(
            conditionLogic: conditionLogic,
            conditionItems: conditionItems,
          );
          final canSubmit =
              name.trim().isNotEmpty && filterContent != null;

          return DialogUtil.createAlertDialog(
            title: Text('video_smart_album_title'.tr),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: '',
                    autofocus: true,
                    onChanged: (v) {
                      name = v;
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: 'photo_album_name'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildConditionEditor(
                    context: context,
                    logic: conditionLogic,
                    onLogicChanged: (v) => setState(() => conditionLogic = v),
                    items: conditionItems,
                    onAdd: () => setState(() {
                      conditionItems.add(_SmartConditionItem.empty());
                    }),
                    onRemove: (idx) => setState(() {
                      if (idx < 0 || idx >= conditionItems.length) return;
                      conditionItems.removeAt(idx).dispose();
                      if (conditionItems.isEmpty) {
                        conditionItems.add(_SmartConditionItem.empty());
                      }
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: closeDialog, child: Text('cancel'.tr)),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        final suc = await controller.createSmartAlbum(
                          name: name.trim(),
                          filterContent: filterContent,
                        );
                        if (suc) closeDialog();
                      }
                    : null,
                child: Text('create'.tr),
              ),
            ],
          );
          },
        );
      },
    );
  } finally {
    await Future<void>.delayed(_smartAlbumDialogDisposeDelay);
    for (final c in conditionItems) {
      c.dispose();
    }
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  VideoSmartAlbumController controller,
  VideoSmartAlbumItem album,
) async {
  var name = album.name;
  var conditionLogic = _parseConditionLogic(album.filterContent);
  final conditionItems = _parseConditionItems(album.filterContent);
  if (conditionItems.isEmpty) {
    conditionItems.add(_SmartConditionItem.empty());
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final nav = Navigator.of(dialogContext);

            void closeDialog() {
              nav.pop();
            }

          final filterContent = _buildFilterContent(
            conditionLogic: conditionLogic,
            conditionItems: conditionItems,
          );
          final canSubmit =
              name.trim().isNotEmpty && filterContent != null;

          return DialogUtil.createAlertDialog(
            title: Text('edit'.tr),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: name,
                    autofocus: true,
                    onChanged: (v) {
                      name = v;
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: 'photo_album_name'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildConditionEditor(
                    context: context,
                    logic: conditionLogic,
                    onLogicChanged: (v) => setState(() => conditionLogic = v),
                    items: conditionItems,
                    onAdd: () => setState(() {
                      conditionItems.add(_SmartConditionItem.empty());
                    }),
                    onRemove: (idx) => setState(() {
                      if (idx < 0 || idx >= conditionItems.length) return;
                      conditionItems.removeAt(idx).dispose();
                      if (conditionItems.isEmpty) {
                        conditionItems.add(_SmartConditionItem.empty());
                      }
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: closeDialog, child: Text('cancel'.tr)),
              ElevatedButton(
                onPressed: canSubmit
                    ? () async {
                        final suc = await controller.updateSmartAlbum(
                          id: album.id,
                          name: name.trim(),
                          filterContent: filterContent,
                        );
                        if (suc) closeDialog();
                      }
                    : null,
                child: Text('save'.tr),
              ),
            ],
          );
          },
        );
      },
    );
  } finally {
    await Future<void>.delayed(_smartAlbumDialogDisposeDelay);
    for (final c in conditionItems) {
      c.dispose();
    }
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  VideoSmartAlbumController controller,
  VideoSmartAlbumItem album,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final nav = Navigator.of(dialogContext);
      return DialogUtil.createAlertDialog(
        title: Text('delete'.tr),
        content: Text("${'delete'.tr} ${album.name}?"),
        actions: [
          TextButton(onPressed: () => nav.pop(), child: Text('cancel'.tr)),
          ElevatedButton(
            onPressed: () async {
              final suc = await controller.deleteSmartAlbum(album.id);
              if (suc) nav.pop();
            },
            child: Text('delete'.tr),
          ),
        ],
      );
    },
  );
}
