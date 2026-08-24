import 'package:NasCabOS/modules/base/components/app_custom_search_dialog.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_card.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_videos_page.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:NasCabOS/modules/video/smart_album/controller/video_smart_album_controller.dart';
import 'package:NasCabOS/modules/video/smart_album/models/video_smart_album_model.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    'nfo_actor',
    'nfo_director',
    'nfo_genres',
    'nfo_regions',
    'path',
    'year',
    'score',
    'duration_min',
  ];

  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<String>(
                value: item.field,
                decoration: InputDecoration(
                  labelText: 'smart_album_condition_field'.tr,
                  border: const OutlineInputBorder(),
                ),
                items: fields
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(_fieldLabelKey(f).tr),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final nextMeta = _conditionFieldMeta(v);
                  if (!nextMeta.valid) return;
                  item.field = v;
                  item.operator = nextMeta.type == _ConditionFieldType.text
                      ? 'contains'
                      : (item.operator == 'gt' ||
                                item.operator == 'eq' ||
                                item.operator == 'lt'
                            ? item.operator
                            : 'gt');
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: isText
                  ? TextField(
                      controller: item.valueCtrl,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                        labelText: 'smart_album_value'.tr,
                        border: const OutlineInputBorder(),
                      ),
                    )
                  : DropdownButtonFormField<String>(
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
                        if (!isNumber) return;
                        if (v == null) return;
                        item.operator = v;
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
        if (isNumber) ...[
          const SizedBox(height: 10),
          TextField(
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
        ],
      ],
    ),
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
            height: 45,
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

class AppVideoSmartAlbumListPage extends StatefulWidget {
  final int? initialEditId;

  const AppVideoSmartAlbumListPage({super.key, this.initialEditId});

  @override
  State<AppVideoSmartAlbumListPage> createState() =>
      _AppVideoSmartAlbumListPageState();
}

class _AppVideoSmartAlbumListPageState
    extends State<AppVideoSmartAlbumListPage> {
  late final String _tag;
  bool _didAutoEdit = false;

  @override
  void initState() {
    super.initState();
    _tag = 'app_video_smart_album_list_${UniqueKey()}';
  }

  List<String> _previewUrls(List<VideoSmartAlbumPreviewItem> previews) {
    return previews.take(4).map((e) {
      final item = VideoHomeItemBean(
        id: 0,
        mediaType: '',
        path: '',
        filename: '',
        firstFilePath: e.firstFilePath,
        nfoName: '',
        nfoYear: 0,
        nfoScore: 0,
        nfoRegions: '',
        nfoGenres: '',
        posterPath: '',
        fanartPath: '',
        logoPath: '',
        progress: 0,
        viewTime: null,
        createTime: null,
        fullPath: e.fullpath,
      );
      return VideoUtils.getPosterUrl(item, size: 500);
    }).toList();
  }

  Future<void> _showMobileSortSheet(VideoSmartAlbumController ctrl) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'sort'.tr,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                ListTile(
                  title: Text('name_asc'.tr),
                  trailing:
                      ctrl.sortField.value == 'name' &&
                          ctrl.sortOrder.value == 'asc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'name', order: 'asc');
                  },
                ),
                ListTile(
                  title: Text('name_desc'.tr),
                  trailing:
                      ctrl.sortField.value == 'name' &&
                          ctrl.sortOrder.value == 'desc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'name', order: 'desc');
                  },
                ),
                ListTile(
                  title: Text('create_time_asc'.tr),
                  trailing:
                      ctrl.sortField.value == 'create_time' &&
                          ctrl.sortOrder.value == 'asc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'create_time', order: 'asc');
                  },
                ),
                ListTile(
                  title: Text('create_time_desc'.tr),
                  trailing:
                      ctrl.sortField.value == 'create_time' &&
                          ctrl.sortOrder.value == 'desc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'create_time', order: 'desc');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog(VideoSmartAlbumController ctrl) async {
    final nameCtrl = TextEditingController();
    var conditionLogic = 'and';
    final conditionItems = <_SmartConditionItem>[_SmartConditionItem.empty()];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filterContent = _buildFilterContent(
              conditionLogic: conditionLogic,
              conditionItems: conditionItems,
            );
            final canSubmit =
                nameCtrl.text.trim().isNotEmpty && filterContent != null;

            return DialogUtil.createAlertDialog(
              title: Text('video_smart_album_title'.tr),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360, maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final nav = Navigator.of(dialogContext);
                          final suc = await ctrl.createSmartAlbum(
                            name: nameCtrl.text.trim(),
                            filterContent: filterContent,
                          );
                          if (suc) nav.pop();
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

    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final c in conditionItems) {
      c.dispose();
    }
    nameCtrl.dispose();
  }

  Future<void> _showEditDialog(
    VideoSmartAlbumController ctrl,
    VideoSmartAlbumItem album,
  ) async {
    final nameCtrl = TextEditingController(text: album.name);
    var conditionLogic = _parseConditionLogic(album.filterContent);
    final conditionItems = _parseConditionItems(album.filterContent);
    if (conditionItems.isEmpty) {
      conditionItems.add(_SmartConditionItem.empty());
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filterContent = _buildFilterContent(
              conditionLogic: conditionLogic,
              conditionItems: conditionItems,
            );
            final canSubmit =
                nameCtrl.text.trim().isNotEmpty && filterContent != null;

            return DialogUtil.createAlertDialog(
              title: Text('edit'.tr),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 360, maxWidth: 640),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final nav = Navigator.of(dialogContext);
                          final suc = await ctrl.updateSmartAlbum(
                            id: album.id,
                            name: nameCtrl.text.trim(),
                            filterContent: filterContent,
                          );
                          if (suc) nav.pop();
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

    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final c in conditionItems) {
      c.dispose();
    }
    nameCtrl.dispose();
  }

  Future<void> _showActions(
    VideoSmartAlbumController ctrl,
    VideoSmartAlbumItem album,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text('open'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(
                    () => AppVideoAlbumVideosPage.smartAlbum(
                      smartAlbumId: album.id,
                      name: album.name,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showEditDialog(ctrl, album);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'tip'.tr,
                    content: '${'delete'.tr} "${album.name}" ?',
                  );
                  if (ok != true) return;
                  await ctrl.deleteSmartAlbum(album.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoSmartAlbumController>(
      init: VideoSmartAlbumController(),
      tag: _tag,
      dispose: (_) => Get.delete<VideoSmartAlbumController>(tag: _tag),
      builder: (ctrl) {
        final content = Obx(() {
          if (!_didAutoEdit && widget.initialEditId != null) {
            VideoSmartAlbumItem? target;
            for (final e in ctrl.items) {
              if (e.id == widget.initialEditId) {
                target = e;
                break;
              }
            }
            if (target != null) {
              _didAutoEdit = true;
              final captured = target;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _showEditDialog(ctrl, captured);
              });
            }
          }

          if (ctrl.isLoading.value && ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.items.isEmpty) {
            return CustomNoData(text: 'no_data'.tr);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width <= 750
                  ? 1
                  : (width / 240).floor().clamp(2, 6);
              return CustomScrollView(
                controller: ctrl.scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: crossAxisCount == 1 ? 2.3 : 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = ctrl.items[index];
                        return AppVideoAlbumCard(
                          title: item.name,
                          titleIcon: Icons.filter_alt_outlined,
                          topLeftIcon: Icons.info_outline,
                          onTopLeftTap: () {
                            final tip = ctrl.buildAlbumTooltip(item) ?? '';
                            DialogUtil.showInfoDialog(
                              title: item.name,
                              content: tip.trim().isEmpty ? 'no_data'.tr : tip,
                            );
                          },
                          previewUrls: _previewUrls(item.previews),
                          onTap: () => Get.to(
                            () => AppVideoAlbumVideosPage.smartAlbum(
                              smartAlbumId: item.id,
                              name: item.name,
                            ),
                          ),
                          onMore: () => _showActions(ctrl, item),
                        );
                      }, childCount: ctrl.items.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Center(
                        child: ctrl.isLoading.value
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : (!ctrl.hasMore.value
                                  ? Text(
                                      'no_more'.tr,
                                      style: Get.textTheme.bodySmall,
                                    )
                                  : OutlinedButton(
                                      onPressed: ctrl.loadMore,
                                      child: Text('load_more'.tr),
                                    )),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        });

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text('video_smart_album_title'.tr),
            actions: [
              Obx(() {
                final hasKeyword = ctrl.keyword.value.isNotEmpty;
                return IconButton(
                  tooltip: 'search'.tr,
                  onPressed: () => AppCustomSearchDialog.show(
                    context: context,
                    hintText: 'search'.tr,
                    controller: ctrl.searchController,
                    onChanged: ctrl.onSearchChanged,
                    onClear: ctrl.clearSearch,
                  ),
                  icon: hasKeyword
                      ? Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.search),
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.search),
                );
              }),
              IconButton(
                tooltip: 'sort'.tr,
                onPressed: () => _showMobileSortSheet(ctrl),
                icon: const Icon(Icons.sort_by_alpha),
              ),
              IconButton(
                tooltip: 'create'.tr,
                onPressed: () => _showCreateDialog(ctrl),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: ctrl.refreshAlbums,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
