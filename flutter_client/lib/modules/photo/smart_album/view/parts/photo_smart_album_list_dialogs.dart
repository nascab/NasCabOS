part of '../photo_smart_album_list_view.dart';

Future<void> _showCreateDialog(
  BuildContext context,
  PhotoSmartAlbumController controller,
) async {
  var name = '';
  var type = 'smart_date';
  var conditionLogic = 'and';
  final conditionItems = <_SmartConditionItem>[];

  var dateMode = 'anniversary';
  var fixedOperator = 'on';
  final now = DateTime.now();
  DateTime? fixedDate = DateTime(now.year, now.month, now.day);
  DateTime? rangeStart;
  DateTime? rangeEnd;
  var anniversaryRepeat = 'year';
  var anniversaryMonth = now.month;
  var anniversaryDay = now.day;

  void disposeLocal() {
    for (final c in conditionItems) {
      c.dispose();
    }
  }

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final nameOk = name.trim().isNotEmpty;
            final filter = _buildFilterContent(
              type: type,
              conditionLogic: conditionLogic,
              conditionItems: conditionItems,
              dateMode: dateMode,
              fixedOperator: fixedOperator,
              fixedDate: fixedDate,
              rangeStart: rangeStart,
              rangeEnd: rangeEnd,
              anniversaryRepeat: anniversaryRepeat,
              anniversaryMonth: anniversaryMonth,
              anniversaryDay: anniversaryDay,
            );

            final canSubmit = nameOk && filter != null;

            return DialogUtil.createAlertDialog(
              title: Text('create'.tr),
              content: _buildSmartAlbumCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                type: type,
                onTypeChanged: (v) => setState(() => type = v),
                conditionLogic: conditionLogic,
                onConditionLogicChanged: (v) =>
                    setState(() => conditionLogic = v),
                conditionItems: conditionItems,
                onAddCondition: () => setState(() {
                  conditionItems.add(_SmartConditionItem.empty());
                }),
                onRemoveCondition: (idx) => setState(() {
                  if (idx < 0 || idx >= conditionItems.length) return;
                  conditionItems.removeAt(idx).dispose();
                }),
                dateMode: dateMode,
                onDateModeChanged: (v) => setState(() => dateMode = v),
                fixedOperator: fixedOperator,
                onFixedOperatorChanged: (v) =>
                    setState(() => fixedOperator = v),
                fixedDate: fixedDate,
                onPickFixedDate: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: fixedDate,
                  );
                  if (picked == null) return;
                  setState(() => fixedDate = picked);
                },
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                onPickRangeStart: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: rangeStart,
                  );
                  if (picked == null) return;
                  setState(() => rangeStart = picked);
                },
                onPickRangeEnd: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: rangeEnd,
                  );
                  if (picked == null) return;
                  setState(() => rangeEnd = picked);
                },
                anniversaryRepeat: anniversaryRepeat,
                onAnniversaryRepeatChanged: (v) =>
                    setState(() => anniversaryRepeat = v),
                anniversaryMonth: anniversaryMonth,
                onAnniversaryMonthChanged: (v) =>
                    setState(() => anniversaryMonth = v),
                anniversaryDay: anniversaryDay,
                onAnniversaryDayChanged: (v) =>
                    setState(() => anniversaryDay = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final payload = _buildFilterContent(
                            type: type,
                            conditionLogic: conditionLogic,
                            conditionItems: conditionItems,
                            dateMode: dateMode,
                            fixedOperator: fixedOperator,
                            fixedDate: fixedDate,
                            rangeStart: rangeStart,
                            rangeEnd: rangeEnd,
                            anniversaryRepeat: anniversaryRepeat,
                            anniversaryMonth: anniversaryMonth,
                            anniversaryDay: anniversaryDay,
                          );
                          if (payload == null) return;
                          final suc = await controller.createSmartAlbum(
                            name: name.trim(),
                            type: type,
                            filterContent: payload,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          }
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
    await Future<void>.delayed(const Duration(milliseconds: 250));
    disposeLocal();
  }
}

Future<void> _showEditDialog(
  BuildContext context,
  PhotoSmartAlbumController controller,
  PhotoSmartAlbumItem album,
) async {
  var name = album.name;
  var type = album.type.isNotEmpty ? album.type : 'condition';

  var conditionLogic = _parseConditionLogic(album.filterContent);
  final conditionItems = _parseConditionItems(album.filterContent);

  var dateMode = _parseDateMode(album.filterContent);
  var fixedOperator = _parseFixedOperator(album.filterContent);
  DateTime? fixedDate = _parseDate(album.filterContent['date']);
  DateTime? rangeStart = _parseDate(album.filterContent['start']);
  DateTime? rangeEnd = _parseDate(album.filterContent['end']);
  var anniversaryRepeat = _parseAnniversaryRepeat(album.filterContent);
  var anniversaryMonth = _parseAnniversaryMonth(album.filterContent);
  var anniversaryDay = _parseAnniversaryDay(album.filterContent);

  void disposeLocal() {
    for (final c in conditionItems) {
      c.dispose();
    }
  }

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final nameOk = name.trim().isNotEmpty;
            final filter = _buildFilterContent(
              type: type,
              conditionLogic: conditionLogic,
              conditionItems: conditionItems,
              dateMode: dateMode,
              fixedOperator: fixedOperator,
              fixedDate: fixedDate,
              rangeStart: rangeStart,
              rangeEnd: rangeEnd,
              anniversaryRepeat: anniversaryRepeat,
              anniversaryMonth: anniversaryMonth,
              anniversaryDay: anniversaryDay,
            );

            final canSubmit = nameOk && filter != null;

            return DialogUtil.createAlertDialog(
              title: Text('edit'.tr),
              content: _buildSmartAlbumCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                type: type,
                onTypeChanged: (v) => setState(() => type = v),
                conditionLogic: conditionLogic,
                onConditionLogicChanged: (v) =>
                    setState(() => conditionLogic = v),
                conditionItems: conditionItems,
                onAddCondition: () => setState(() {
                  conditionItems.add(_SmartConditionItem.empty());
                }),
                onRemoveCondition: (idx) => setState(() {
                  if (idx < 0 || idx >= conditionItems.length) return;
                  conditionItems.removeAt(idx).dispose();
                }),
                dateMode: dateMode,
                onDateModeChanged: (v) => setState(() => dateMode = v),
                fixedOperator: fixedOperator,
                onFixedOperatorChanged: (v) =>
                    setState(() => fixedOperator = v),
                fixedDate: fixedDate,
                onPickFixedDate: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: fixedDate,
                  );
                  if (picked == null) return;
                  setState(() => fixedDate = picked);
                },
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                onPickRangeStart: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: rangeStart,
                  );
                  if (picked == null) return;
                  setState(() => rangeStart = picked);
                },
                onPickRangeEnd: () async {
                  final picked = await _pickDate(
                    context: dialogContext,
                    initial: rangeEnd,
                  );
                  if (picked == null) return;
                  setState(() => rangeEnd = picked);
                },
                anniversaryRepeat: anniversaryRepeat,
                onAnniversaryRepeatChanged: (v) =>
                    setState(() => anniversaryRepeat = v),
                anniversaryMonth: anniversaryMonth,
                onAnniversaryMonthChanged: (v) =>
                    setState(() => anniversaryMonth = v),
                anniversaryDay: anniversaryDay,
                onAnniversaryDayChanged: (v) =>
                    setState(() => anniversaryDay = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final payload = _buildFilterContent(
                            type: type,
                            conditionLogic: conditionLogic,
                            conditionItems: conditionItems,
                            dateMode: dateMode,
                            fixedOperator: fixedOperator,
                            fixedDate: fixedDate,
                            rangeStart: rangeStart,
                            rangeEnd: rangeEnd,
                            anniversaryRepeat: anniversaryRepeat,
                            anniversaryMonth: anniversaryMonth,
                            anniversaryDay: anniversaryDay,
                          );
                          if (payload == null) return;
                          final suc = await controller.updateSmartAlbum(
                            id: album.id,
                            name: name.trim(),
                            type: type,
                            filterContent: payload,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          }
                        }
                      : null,
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    disposeLocal();
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  PhotoSmartAlbumController controller,
  PhotoSmartAlbumItem album,
) async {
  final ok = await DialogUtil.showConfirmDialog(
    title: 'need_confirm'.tr,
    content: "${'confirm_delete'.tr}[${album.name}]",
    confirmText: 'confirm'.tr,
    cancelText: 'cancel'.tr,
  );
  if (ok == true) {
    await controller.deleteSmartAlbum(album.id);
  }
}

Widget _buildSmartAlbumCreateEditDialogContent({
  required BuildContext context,
  required String nameValue,
  required ValueChanged<String> onNameChanged,
  required String type,
  required ValueChanged<String> onTypeChanged,
  required String conditionLogic,
  required ValueChanged<String> onConditionLogicChanged,
  required List<_SmartConditionItem> conditionItems,
  required VoidCallback onAddCondition,
  required ValueChanged<int> onRemoveCondition,
  required String dateMode,
  required ValueChanged<String> onDateModeChanged,
  required String fixedOperator,
  required ValueChanged<String> onFixedOperatorChanged,
  required DateTime? fixedDate,
  required Future<void> Function() onPickFixedDate,
  required DateTime? rangeStart,
  required DateTime? rangeEnd,
  required Future<void> Function() onPickRangeStart,
  required Future<void> Function() onPickRangeEnd,
  required String anniversaryRepeat,
  required ValueChanged<String> onAnniversaryRepeatChanged,
  required int anniversaryMonth,
  required ValueChanged<int> onAnniversaryMonthChanged,
  required int anniversaryDay,
  required ValueChanged<int> onAnniversaryDayChanged,
}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 360, maxWidth: 560),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          initialValue: nameValue,
          autofocus: true,
          onChanged: onNameChanged,
          decoration: InputDecoration(
            labelText: 'photo_album_name'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: type,
          decoration: InputDecoration(
            labelText: 'type'.tr,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'smart_date',
              child: Text('smart_date_album'.tr),
            ),
            DropdownMenuItem(
              value: 'condition',
              child: Text('condition_album'.tr),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onTypeChanged(v);
          },
        ),
        const SizedBox(height: 12),
        if (type == 'smart_date')
          _buildSmartDateEditor(
            context: context,
            mode: dateMode,
            onModeChanged: onDateModeChanged,
            fixedOperator: fixedOperator,
            onFixedOperatorChanged: onFixedOperatorChanged,
            fixedDate: fixedDate,
            onPickFixedDate: onPickFixedDate,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            onPickRangeStart: onPickRangeStart,
            onPickRangeEnd: onPickRangeEnd,
            anniversaryRepeat: anniversaryRepeat,
            onAnniversaryRepeatChanged: onAnniversaryRepeatChanged,
            anniversaryMonth: anniversaryMonth,
            onAnniversaryMonthChanged: onAnniversaryMonthChanged,
            anniversaryDay: anniversaryDay,
            onAnniversaryDayChanged: onAnniversaryDayChanged,
          )
        else
          _buildConditionEditor(
            context: context,
            logic: conditionLogic,
            onLogicChanged: onConditionLogicChanged,
            items: conditionItems,
            onAdd: onAddCondition,
            onRemove: onRemoveCondition,
          ),
      ],
    ),
  );
}

Widget _buildSmartDateEditor({
  required BuildContext context,
  required String mode,
  required ValueChanged<String> onModeChanged,
  required String fixedOperator,
  required ValueChanged<String> onFixedOperatorChanged,
  required DateTime? fixedDate,
  required Future<void> Function() onPickFixedDate,
  required DateTime? rangeStart,
  required DateTime? rangeEnd,
  required Future<void> Function() onPickRangeStart,
  required Future<void> Function() onPickRangeEnd,
  required String anniversaryRepeat,
  required ValueChanged<String> onAnniversaryRepeatChanged,
  required int anniversaryMonth,
  required ValueChanged<int> onAnniversaryMonthChanged,
  required int anniversaryDay,
  required ValueChanged<int> onAnniversaryDayChanged,
}) {
  final inputBorder = const OutlineInputBorder();
  final locale = Get.locale ?? Localizations.localeOf(context);

  String monthLabel(int month) {
    return DateFormat.MMMM(locale.toString()).format(DateTime(2000, month, 1));
  }

  Widget rowLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DropdownButtonFormField<String>(
        value: mode,
        decoration: InputDecoration(
          labelText: 'smart_album_date_mode'.tr,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: 'fixed',
            child: Text('smart_album_date_mode_fixed'.tr),
          ),
          DropdownMenuItem(
            value: 'range',
            child: Text('smart_album_date_mode_range'.tr),
          ),
          DropdownMenuItem(
            value: 'anniversary',
            child: Text('smart_album_date_mode_anniversary'.tr),
          ),
        ],
        onChanged: (v) {
          if (v == null) return;
          onModeChanged(v);
        },
      ),
      const SizedBox(height: 12),
      if (mode == 'fixed') ...[
        DropdownButtonFormField<String>(
          value: fixedOperator,
          decoration: InputDecoration(
            labelText: 'smart_album_date_condition'.tr,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'on',
              child: Text('smart_album_date_op_on'.tr),
            ),
            DropdownMenuItem(
              value: 'before',
              child: Text('smart_album_date_op_before_inclusive'.tr),
            ),
            DropdownMenuItem(
              value: 'after',
              child: Text('smart_album_date_op_after_inclusive'.tr),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onFixedOperatorChanged(v);
          },
        ),
        const SizedBox(height: 12),
        rowLabel('smart_album_date_label_date'.tr),
        InkWell(
          onTap: onPickFixedDate,
          child: InputDecorator(
            decoration: InputDecoration(
              border: inputBorder,
              suffixIcon: const Icon(Icons.event_outlined),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            child: Text(
              fixedDate == null
                  ? 'smart_album_date_pick'.tr
                  : _formatDate(fixedDate),
            ),
          ),
        ),
      ],
      if (mode == 'range') ...[
        rowLabel('smart_album_date_label_start'.tr),
        InkWell(
          onTap: onPickRangeStart,
          child: InputDecorator(
            decoration: InputDecoration(
              border: inputBorder,
              suffixIcon: const Icon(Icons.event_outlined),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            child: Text(
              rangeStart == null
                  ? 'smart_album_date_pick_start'.tr
                  : _formatDate(rangeStart),
            ),
          ),
        ),
        const SizedBox(height: 12),
        rowLabel('smart_album_date_label_end'.tr),
        InkWell(
          onTap: onPickRangeEnd,
          child: InputDecorator(
            decoration: InputDecoration(
              border: inputBorder,
              suffixIcon: const Icon(Icons.event_outlined),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            child: Text(
              rangeEnd == null
                  ? 'smart_album_date_pick_end'.tr
                  : _formatDate(rangeEnd),
            ),
          ),
        ),
      ],
      if (mode == 'anniversary') ...[
        DropdownButtonFormField<String>(
          value: anniversaryRepeat,
          decoration: InputDecoration(
            labelText: 'smart_album_repeat'.tr,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'year',
              child: Text('smart_album_repeat_year'.tr),
            ),
            DropdownMenuItem(
              value: 'month',
              child: Text('smart_album_repeat_month'.tr),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onAnniversaryRepeatChanged(v);
          },
        ),
        const SizedBox(height: 12),
        if (anniversaryRepeat == 'year') ...[
          DropdownButtonFormField<int>(
            value: anniversaryMonth,
            decoration: InputDecoration(
              labelText: 'smart_album_month'.tr,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (int m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(monthLabel(m))),
            ],
            onChanged: (v) {
              if (v == null) return;
              onAnniversaryMonthChanged(v);
            },
          ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<int>(
          value: anniversaryDay,
          decoration: InputDecoration(
            labelText: 'smart_album_day'.tr,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (int d = 1; d <= 31; d++)
              DropdownMenuItem(value: d, child: Text('$d')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onAnniversaryDayChanged(v);
          },
        ),
      ],
    ],
  );
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
      if (items.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('smart_album_condition_min_one'.tr),
        )
      else
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
  required VoidCallback onRemove,
  required VoidCallback onChanged,
}) {
  final isText =
      _conditionFieldMeta(item.field).type == _ConditionFieldType.text;
  final isNumber =
      _conditionFieldMeta(item.field).type == _ConditionFieldType.number;

  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
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
                  DropdownMenuItem(
                    value: 'filename',
                    child: Text('filename'.tr),
                  ),
                  DropdownMenuItem(value: 'path', child: Text('path'.tr)),
                  DropdownMenuItem(
                    value: 'camera',
                    child: Text('smart_album_field_camera'.tr),
                  ),
                  DropdownMenuItem(
                    value: 'size_mb',
                    child: Text('${'size'.tr}(${'smart_album_unit_mb'.tr})'),
                  ),
                  DropdownMenuItem(
                    value: 'duration_min',
                    child: Text(
                      '${'smart_album_field_duration'.tr}(${'smart_album_unit_min'.tr})',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'width',
                    child: Text(
                      '${'smart_album_field_width'.tr}(${'smart_album_unit_px'.tr})',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'height',
                    child: Text(
                      '${'smart_album_field_height'.tr}(${'smart_album_unit_px'.tr})',
                    ),
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
        if (isText) ...[
          TextField(
            controller: item.valueCtrl,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'smart_album_operator_contains'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (isNumber) ...[
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
      ],
    ),
  );
}

Future<DateTime?> _pickDate({
  required BuildContext context,
  DateTime? initial,
}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    locale: Get.locale ?? Localizations.localeOf(context),
    initialDate: initial ?? DateTime(now.year, now.month, now.day),
    firstDate: DateTime(1970, 1, 1),
    lastDate: DateTime(2100, 12, 31),
  );
}

String _formatDate(DateTime? d) {
  if (d == null) return '';
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

Map<String, dynamic>? _buildFilterContent({
  required String type,
  required String conditionLogic,
  required List<_SmartConditionItem> conditionItems,
  required String dateMode,
  required String fixedOperator,
  required DateTime? fixedDate,
  required DateTime? rangeStart,
  required DateTime? rangeEnd,
  required String anniversaryRepeat,
  required int anniversaryMonth,
  required int anniversaryDay,
}) {
  if (type == 'smart_date') {
    if (dateMode == 'fixed') {
      if (fixedDate == null) return null;
      return {
        'mode': 'fixed',
        'operator': fixedOperator,
        'date': _formatDate(fixedDate),
      };
    }
    if (dateMode == 'range') {
      if (rangeStart == null || rangeEnd == null) return null;
      return {
        'mode': 'range',
        'start': _formatDate(rangeStart),
        'end': _formatDate(rangeEnd),
      };
    }
    if (dateMode == 'anniversary') {
      if (anniversaryRepeat == 'year') {
        return {
          'mode': 'anniversary',
          'repeat': 'year',
          'month': anniversaryMonth,
          'day': anniversaryDay,
        };
      }
      return {'mode': 'anniversary', 'repeat': 'month', 'day': anniversaryDay};
    }
    return null;
  }

  final mapped = <Map<String, dynamic>>[];
  for (final item in conditionItems) {
    final meta = _conditionFieldMeta(item.field);
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

String _parseDateMode(Map<String, dynamic> filterContent) {
  final m = filterContent['mode']?.toString();
  if (m == 'anniversary' || m == 'fixed' || m == 'range') return m!;
  return 'fixed';
}

String _parseFixedOperator(Map<String, dynamic> filterContent) {
  final v = filterContent['operator']?.toString();
  if (v == 'before' || v == 'after' || v == 'on') return v!;
  return 'on';
}

String _parseAnniversaryRepeat(Map<String, dynamic> filterContent) {
  final v = filterContent['repeat']?.toString();
  if (v == 'month' || v == 'year') return v!;
  return 'year';
}

int _parseAnniversaryMonth(Map<String, dynamic> filterContent) {
  final n = (filterContent['month'] as num?)?.toInt();
  if (n == null) return 1;
  return n.clamp(1, 12);
}

int _parseAnniversaryDay(Map<String, dynamic> filterContent) {
  final n = (filterContent['day'] as num?)?.toInt();
  if (n == null) return 1;
  return n.clamp(1, 31);
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final dt = DateTime.tryParse('${s}T00:00:00Z');
  if (dt == null) return null;
  return DateTime(dt.year, dt.month, dt.day);
}

enum _ConditionFieldType { text, number, invalid }

class _ConditionFieldMeta {
  final _ConditionFieldType type;
  final bool valid;
  const _ConditionFieldMeta({required this.type, required this.valid});
}

_ConditionFieldMeta _conditionFieldMeta(String field) {
  switch (field) {
    case 'filename':
    case 'path':
    case 'camera':
      return const _ConditionFieldMeta(
        type: _ConditionFieldType.text,
        valid: true,
      );
    case 'size_mb':
    case 'duration_min':
    case 'width':
    case 'height':
      return const _ConditionFieldMeta(
        type: _ConditionFieldType.number,
        valid: true,
      );
    default:
      return const _ConditionFieldMeta(
        type: _ConditionFieldType.invalid,
        valid: false,
      );
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
    return _SmartConditionItem(field: 'filename', operator: 'contains');
  }

  void dispose() {
    valueCtrl.dispose();
  }
}
