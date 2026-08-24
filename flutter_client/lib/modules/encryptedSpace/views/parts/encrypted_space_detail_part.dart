part of '../encrypted_space_view.dart';

class EncryptedSpaceDetailPage extends StatelessWidget {
  const EncryptedSpaceDetailPage({
    super.key,
    required this.spaceId,
    required this.token,
    this.name,
  });

  final int spaceId;
  final String token;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EncryptedSpaceDetailPanel(
        spaceId: spaceId,
        token: token,
        name: name,
        onClose: () => Get.back(),
      ),
    );
  }
}

class _EncryptedSpaceDetailOverlay extends StatelessWidget {
  const _EncryptedSpaceDetailOverlay({
    required this.active,
    required this.onClose,
  });

  final EncryptedSpaceActiveSpace active;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: EncryptedSpaceDetailPanel(
                  key: ValueKey('encrypted_space_detail_${active.spaceId}'),
                  spaceId: active.spaceId,
                  token: active.token,
                  name: active.name,
                  path: active.path,
                  onClose: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EncryptedSpaceDetailPanel extends StatelessWidget {
  const EncryptedSpaceDetailPanel({
    super.key,
    required this.spaceId,
    required this.token,
    this.name,
    this.path,
    this.onClose,
  });

  final int spaceId;
  final String token;
  final String? name;
  final String? path;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<EncryptedSpaceDetailController>(
      init: EncryptedSpaceDetailController(spaceId: spaceId, token: token),
      global: false,
      builder: (ctrl) {
        final title = (name ?? '').trim().isNotEmpty
            ? name!.trim()
            : '$spaceId';
        final pathText = (path ?? '').trim();
        final displayTitle = pathText.isEmpty
            ? title
            : '$title · ${'path'.tr}: $pathText';
        final listArea = DeviceUtils.isWeb
            ? UploadWebFolderDropTargetWrapper(
                onDropDataTransfer: ctrl.uploadDroppedWebDataTransfer,
                child: _EncryptedSpaceDetailBody(ctrl: ctrl),
              )
            : PcFileDropTargetWrapper(
                onDragDone: ctrl.uploadDroppedFiles,
                child: _EncryptedSpaceDetailBody(ctrl: ctrl),
              );

        return Stack(
          children: [
            Column(
              children: [
                _EncryptedSpaceDetailTopBar(
                  title: displayTitle,
                  ctrl: ctrl,
                  onClose: onClose,
                ),
                _EncryptedSpaceDetailToolbar(ctrl: ctrl, onClose: onClose),
                Expanded(child: listArea),
              ],
            ),
            _EncryptedSpaceUploadProgressOverlay(ctrl: ctrl),
          ],
        );
      },
    );
  }
}

class _EncryptedSpaceUploadProgressOverlay extends StatelessWidget {
  const _EncryptedSpaceUploadProgressOverlay({required this.ctrl});

  final EncryptedSpaceDetailController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!ctrl.isUploading.value) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final file = ctrl.uploadingFileName.value.trim();
      final idx = ctrl.uploadingIndex.value;
      final total = ctrl.uploadingTotal.value;
      final pct = (ctrl.uploadingProgress.value.clamp(0.0, 1.0) * 100)
          .toStringAsFixed(0);
      final text = [
        if (file.isNotEmpty) file,
        if (idx > 0 && total > 0) '$idx/$total',
        '$pct%',
      ].join(' ');

      return Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: SafeArea(
          top: false,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: ctrl.uploadingProgress.value.clamp(0.0, 1.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'cancel'.tr,
                    onPressed: () => ctrl.cancelUploadFlow(),
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _EncryptedSpaceDetailTopBar extends StatelessWidget {
  const _EncryptedSpaceDetailTopBar({
    required this.title,
    required this.ctrl,
    this.onClose,
  });

  final String title;
  final EncryptedSpaceDetailController ctrl;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.only(left: 72, right: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _EncryptedSpaceDetailToolbar extends StatelessWidget {
  const _EncryptedSpaceDetailToolbar({required this.ctrl, this.onClose});

  final EncryptedSpaceDetailController ctrl;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EncryptedSpaceDetailSortSearchBar(ctrl: ctrl, onClose: onClose),
      ],
    );
  }
}

/// 排序 + 搜索 + 操作按钮行
class _EncryptedSpaceDetailSortSearchBar extends StatefulWidget {
  const _EncryptedSpaceDetailSortSearchBar({required this.ctrl, this.onClose});

  final EncryptedSpaceDetailController ctrl;
  final VoidCallback? onClose;

  @override
  State<_EncryptedSpaceDetailSortSearchBar> createState() =>
      _EncryptedSpaceDetailSortSearchBarState();
}

class _EncryptedSpaceDetailSortSearchBarState
    extends State<_EncryptedSpaceDetailSortSearchBar> {
  EncryptedSpaceDetailController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            CustomBorderedIconButton(
              icon: Icons.close,
              tooltip: 'back'.tr,
              onTap: widget.onClose ?? () => Get.back(),
            ),
            const SizedBox(width: 8),
            const Spacer(),
            CustomExpandableSearchBar(
              hintText: 'search'.tr,
              onChanged: ctrl.onSearchChanged,
              onClear: ctrl.clearSearch,
            ),
            const SizedBox(width: 8),
            Obx(() {
              final cur = '${ctrl.sortField.value}_${ctrl.sortOrder.value}';
              return CustomPopupSelectButton<String>(
                icon: Icons.sort_by_alpha,
                tooltip: 'sort'.tr,
                value: cur,
                defaultValue: 'show_name_asc',
                items: [
                  CustomPopupSelectItem(
                    value: 'show_name_asc',
                    label: 'name_asc'.tr,
                    icon: Icons.sort_by_alpha,
                  ),
                  CustomPopupSelectItem(
                    value: 'show_name_desc',
                    label: 'name_desc'.tr,
                    icon: Icons.sort_by_alpha,
                  ),
                  CustomPopupSelectItem(
                    value: 'create_time_asc',
                    label: 'photo_album_sort_create_time_asc'.tr,
                    icon: Icons.schedule,
                  ),
                  CustomPopupSelectItem(
                    value: 'create_time_desc',
                    label: 'photo_album_sort_create_time_desc'.tr,
                    icon: Icons.schedule,
                  ),
                  CustomPopupSelectItem(
                    value: 'original_time_asc',
                    label: 'photo_timeline_sort_asc'.tr,
                    icon: Icons.camera_alt_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'original_time_desc',
                    label: 'photo_timeline_sort_desc'.tr,
                    icon: Icons.camera_alt_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'size_asc',
                    label: 'folder_picker_sort_size_asc'.tr,
                    icon: Icons.storage,
                  ),
                  CustomPopupSelectItem(
                    value: 'size_desc',
                    label: 'folder_picker_sort_size_desc'.tr,
                    icon: Icons.storage,
                  ),
                  CustomPopupSelectItem(
                    value: 'duration_asc',
                    label: 'music_list_sort_duration_asc'.tr,
                    icon: Icons.timer_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'duration_desc',
                    label: 'music_list_sort_duration_desc'.tr,
                    icon: Icons.timer_outlined,
                  ),
                ],
                onSelected: (next) {
                  final parts = next.split('_');
                  if (parts.length < 2) return;
                  final order = parts.last;
                  final field = parts.sublist(0, parts.length - 1).join('_');
                  ctrl.setSort(field: field, order: order);
                },
              );
            }),
            const SizedBox(width: 8),
            Obx(() {
              final cur = ctrl.fileTypeFilter.value;
              return CustomPopupSelectButton<String>(
                icon: Icons.filter_alt_outlined,
                tooltip: 'filter'.tr,
                value: cur,
                defaultValue: 'all',
                items: [
                  CustomPopupSelectItem(
                    value: 'all',
                    label: 'all'.tr,
                    icon: Icons.filter_alt_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'image',
                    label: 'file_type_image'.tr,
                    icon: Icons.image_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'video',
                    label: 'file_type_video'.tr,
                    icon: Icons.video_file_outlined,
                  ),
                  CustomPopupSelectItem(
                    value: 'other',
                    label: 'encrypted_space_filter_other'.tr,
                    icon: Icons.insert_drive_file_outlined,
                  ),
                ],
                onSelected: ctrl.setFileTypeFilter,
              );
            }),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.refresh,
              tooltip: 'refresh'.tr,
              onTap: () => ctrl.refreshList(showLoading: true),
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.upload_file,
              tooltip: 'upload'.tr,
              onTap: () => ctrl.uploadFilesFlow(),
            ),
          ],
        ),
      ),
    );
  }
}
