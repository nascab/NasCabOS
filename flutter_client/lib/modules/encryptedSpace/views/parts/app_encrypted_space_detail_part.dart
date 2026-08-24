part of '../encrypted_space_view.dart';

/// 加密空间文件列表排序项，用于 App 端底部栏
class _EncryptedSpaceSortEntry {
  final String field;
  final String order;
  final String labelKey;

  const _EncryptedSpaceSortEntry({
    required this.field,
    required this.order,
    required this.labelKey,
  });
}

List<_EncryptedSpaceSortEntry> _getEncryptedSpaceSortEntries() {
  return const [
    _EncryptedSpaceSortEntry(
      field: 'show_name',
      order: 'asc',
      labelKey: 'name_asc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'show_name',
      order: 'desc',
      labelKey: 'name_desc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'create_time',
      order: 'asc',
      labelKey: 'photo_album_sort_create_time_asc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'create_time',
      order: 'desc',
      labelKey: 'photo_album_sort_create_time_desc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'original_time',
      order: 'asc',
      labelKey: 'photo_timeline_sort_asc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'original_time',
      order: 'desc',
      labelKey: 'photo_timeline_sort_desc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'size',
      order: 'asc',
      labelKey: 'folder_picker_sort_size_asc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'size',
      order: 'desc',
      labelKey: 'folder_picker_sort_size_desc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'duration',
      order: 'asc',
      labelKey: 'music_list_sort_duration_asc',
    ),
    _EncryptedSpaceSortEntry(
      field: 'duration',
      order: 'desc',
      labelKey: 'music_list_sort_duration_desc',
    ),
  ];
}

String? _getEncryptedSpaceDetailSortLabelKey(
  EncryptedSpaceDetailController ctrl,
) {
  final field = ctrl.sortField.value;
  final order = ctrl.sortOrder.value;
  for (final e in _getEncryptedSpaceSortEntries()) {
    if (e.field == field && e.order == order) return e.labelKey;
  }
  return null;
}

String _getFileTypeFilterLabel(String value) {
  switch (value) {
    case 'all':
      return 'all'.tr;
    case 'image':
      return 'file_type_image'.tr;
    case 'video':
      return 'file_type_video'.tr;
    case 'other':
      return 'encrypted_space_filter_other'.tr;
    default:
      return 'all'.tr;
  }
}

const _fileTypeFilterOptions = ['all', 'image', 'video', 'other'];

class AppEncryptedSpaceDetailPage extends StatelessWidget {
  const AppEncryptedSpaceDetailPage({
    super.key,
    required this.active,
    required this.ctrl,
  });

  final EncryptedSpaceActiveSpace active;
  final EncryptedSpaceController ctrl;

  Future<void> _openSortSheet(
    BuildContext context,
    EncryptedSpaceDetailController detailCtrl,
  ) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final e in _getEncryptedSpaceSortEntries())
                  ListTile(
                    dense: true,
                    leading:
                        detailCtrl.sortField.value == e.field &&
                            detailCtrl.sortOrder.value == e.order
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox(width: 24),
                    title: Text(e.labelKey.tr),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      detailCtrl.setSort(field: e.field, order: e.order);
                    },
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  Future<void> _openFileTypeFilterSheet(
    BuildContext context,
    EncryptedSpaceDetailController detailCtrl,
  ) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return Material(
          color: theme.colorScheme.surface,
          child: Obx(() {
            final cur = detailCtrl.fileTypeFilter.value;
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final value in _fileTypeFilterOptions)
                  ListTile(
                    dense: true,
                    leading: cur == value
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox(width: 24),
                    title: Text(_getFileTypeFilterLabel(value)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      detailCtrl.setFileTypeFilter(value);
                    },
                  ),
              ],
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = active.name.trim().isNotEmpty ? active.name.trim() : null;
    final title = name ?? '${active.spaceId}';

    return GetBuilder<EncryptedSpaceDetailController>(
      init: EncryptedSpaceDetailController(
        spaceId: active.spaceId,
        token: active.token,
      ),
      global: false,
      builder: (detailCtrl) {
        return WillPopScope(
          onWillPop: () async {
            ctrl.closeActiveSpace();
            return true;
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () {
                  ctrl.closeActiveSpace();
                  Get.back();
                },
              ),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [],
            ),
            body: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 搜索在最左，排序、类型筛选、上传靠右
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Obx(() {
                        final isDefaultSort =
                            detailCtrl.sortField.value == 'original_time' &&
                            detailCtrl.sortOrder.value == 'desc';
                        final labelKey = _getEncryptedSpaceDetailSortLabelKey(
                          detailCtrl,
                        );
                        final sortTooltip = labelKey != null
                            ? labelKey.tr
                            : 'sort'.tr;
                        final filterText = _getFileTypeFilterLabel(
                          detailCtrl.fileTypeFilter.value,
                        );
                        final isFilterActive =
                            detailCtrl.fileTypeFilter.value != 'all';
                        return Row(
                          children: [
                            Flexible(
                              child: CustomExpandableSearchBar(
                                hintText: 'search'.tr,
                                onChanged: detailCtrl.onSearchChanged,
                                onClear: detailCtrl.clearSearch,
                                defaultExpanded: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            CustomBorderedIconButton(
                              icon: Icons.sort_by_alpha,
                              tooltip: sortTooltip,
                              active: !isDefaultSort,
                              onTap: () => _openSortSheet(context, detailCtrl),
                            ),
                            const SizedBox(width: 8),
                            CustomBorderedIconButton(
                              icon: Icons.filter_alt_outlined,
                              tooltip: filterText,
                              active: isFilterActive,
                              onTap: () =>
                                  _openFileTypeFilterSheet(context, detailCtrl),
                            ),
                            const SizedBox(width: 8),
                            CustomBorderedIconButton(
                              icon: Icons.upload_file,
                              tooltip: 'upload'.tr,
                              onTap: () => detailCtrl.uploadFilesFlow(),
                            ),
                          ],
                        );
                      }),
                    ),
                    Expanded(
                      child: _EncryptedSpaceDetailBody(
                        ctrl: detailCtrl,
                        onRefresh: () =>
                            detailCtrl.refreshList(showLoading: false),
                      ),
                    ),
                  ],
                ),
                _EncryptedSpaceUploadProgressOverlay(ctrl: detailCtrl),
              ],
            ),
          ),
        );
      },
    );
  }
}
