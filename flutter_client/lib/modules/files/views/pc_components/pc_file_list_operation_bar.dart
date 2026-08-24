import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../utils/dialog_util.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../../transfer/controllers/upload_controller.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../../utils/popup_menu_util.dart';
import 'pc_internal_drag_item.dart';

/// 右侧顶部操作栏：新建/上传/删除 + 排序/视图/筛选
class PcFileListOperationBar extends StatelessWidget {
  PcFileListOperationBar({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;

  final _newKey = GlobalKey();
  final _uploadKey = GlobalKey();
  final _sortKey = GlobalKey();
  final _filterKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isRecent = ctrl.currentModule.value == 'recent';
      final isFavorites = ctrl.currentModule.value == 'favorites';
      final canPasteHere = !isRecent && !isFavorites;
      final searching = ctrl.searchQuery.value.trim().isNotEmpty;
      final hoverMenusDisabled = PcInternalDragSession.isDragging;
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      key: _newKey,
                      padding: EdgeInsets.zero,
                      child: CustomBorderedIconButton(
                        tooltip: 'folder_action_new'.tr,
                        icon: Icons.create_new_folder_outlined,
                        onTap: () async {
                          final result =
                              await PopupMenuUtil.showBelowButton<String>(
                                context: context,
                                buttonKey: _newKey,
                                items: [
                                  _popupItem(
                                    value: 'dir',
                                    icon: Icons.folder_open_outlined,
                                    label: 'folder_new_dir'.tr,
                                  ),
                                  _popupItem(
                                    value: 'txt',
                                    icon: Icons.description_outlined,
                                    label: 'folder_new_txt'.tr,
                                  ),
                                  _popupItem(
                                    value: 'md',
                                    icon: Icons.description_outlined,
                                    label: 'folder_new_md'.tr,
                                  ),
                                ],
                              );
                          if (result == null) return;
                          if (result == 'dir') {
                            final supported = await ctrl
                                .ensureCreateFolderSupported();
                            if (!supported) return;
                            if (!context.mounted) return;
                            final name = await _inputDialog(
                              context,
                              'folder_new_dir'.tr,
                            );
                            if (name != null && name.isNotEmpty) {
                              await ctrl.createFolder(name);
                            }
                          } else if (result == 'txt' || result == 'md') {
                            final supported = await ctrl
                                .ensureCreateFileSupported();
                            if (!supported) return;
                            if (!context.mounted) return;
                            final ext = result == 'txt' ? '.txt' : '.md';
                            final title = result == 'txt'
                                ? 'folder_new_txt'.tr
                                : 'folder_new_md'.tr;
                            final name = await _inputFileDialog(
                              context,
                              title: title,
                              ext: ext,
                            );
                            if (name != null && name.isNotEmpty) {
                              await ctrl.createTextFileAndOpen(
                                name: name,
                                type: result,
                              );
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      key: _uploadKey,
                      padding: EdgeInsets.zero,
                      child: CustomBorderedIconButton(
                        tooltip: 'upload'.tr,
                        icon: Icons.upload_file_outlined,
                        onTap: () async {
                          final result =
                              await PopupMenuUtil.showBelowButton<String>(
                                context: context,
                                buttonKey: _uploadKey,
                                items: [
                                  _popupItem(
                                    value: 'file',
                                    icon: Icons.insert_drive_file_outlined,
                                    label: 'folder_upload_file'.tr,
                                  ),
                                  _popupItem(
                                    value: 'dir',
                                    icon: Icons.folder_open_outlined,
                                    label: 'folder_upload_dir'.tr,
                                  ),
                                ],
                              );
                          if (result == null) return;
                          final tc = Get.put(
                            UploadController(),
                            permanent: true,
                          );
                          final target = ctrl.currentPath.value ?? '/';
                          // Web/Safari: 文件选择器必须在用户手势中同步触发，不能先 await，否则 Safari 会拦截
                          final ensureSupported = kIsWeb
                              ? () => ctrl.ensureUploadSupported()
                              : null;
                          if (kIsWeb) {
                            if (result == 'file') {
                              tc.pickAndUpload(
                                target,
                                ensureSupported: ensureSupported,
                              );
                            } else if (result == 'dir') {
                              tc.pickAndUploadFolder(
                                target,
                                ensureSupported: ensureSupported,
                              );
                            }
                          } else {
                            final supported = await ctrl
                                .ensureUploadSupported();
                            if (!supported) return;
                            if (result == 'file') {
                              tc.pickAndUpload(target);
                            } else if (result == 'dir') {
                              tc.pickAndUploadFolder(target);
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Obx(
                      () => CustomBorderedIconButton(
                        tooltip: ctrl.showHidden.value
                            ? 'file_tooltip_hide_hidden'.tr
                            : 'file_tooltip_show_hidden'.tr,
                        icon: ctrl.showHidden.value
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        active: ctrl.showHidden.value,
                        onTap: () => ctrl.toggleShowHidden(),
                      ),
                    ),
                    if (ctrl.clipboardItems.isNotEmpty && canPasteHere) ...[
                      const SizedBox(width: 4),
                      CustomBorderedIconButton(
                        tooltip: 'file_paste'.tr,
                        icon: Icons.paste_outlined,
                        onTap: () => ctrl.pasteFromClipboard(),
                      ),
                    ],
                    if (isRecent) ...[
                      const SizedBox(width: 4),
                      CustomBorderedIconButton(
                        tooltip: 'recent_clear'.tr,
                        icon: Icons.delete_sweep_outlined,
                        onTap: () async {
                          final confirmed = await DialogUtil.showConfirmDialog(
                            title: 'need_confirm'.tr,
                            content: 'recent_clear_confirm'.tr,
                            confirmText: 'ok'.tr,
                            cancelText: 'cancel'.tr,
                          );
                          if (confirmed ?? false) {
                            final ok = await ctrl.clearRecent();
                            if (!ok) {
                              DialogUtil.showErrorDialog(
                                message: 'operation_failed'.tr,
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(width: 4),
            // 排序
            if (!isRecent)
              IgnorePointer(
                ignoring: hoverMenusDisabled,
                child: Padding(
                  key: _sortKey,
                  padding: EdgeInsets.zero,
                  child: Obx(
                    () => CustomBorderedIconButton(
                      tooltip: 'sort'.tr,
                      icon: Icons.sort_by_alpha,
                      active: ctrl.sortMode.value != 'name_asc',
                      onTap: () async {
                        final result =
                            await PopupMenuUtil.showBelowButton<String>(
                              context: context,
                              buttonKey: _sortKey,
                              items: [
                                _popupItem(
                                  value: 'name_asc',
                                  icon: Icons.sort_by_alpha_outlined,
                                  label: "${'folder_sort_name'.tr} ↑",
                                  selected: ctrl.sortMode.value == 'name_asc',
                                ),
                                _popupItem(
                                  value: 'name_desc',
                                  icon: Icons.sort_by_alpha_outlined,
                                  label: "${'folder_sort_name'.tr} ↓",
                                  selected: ctrl.sortMode.value == 'name_desc',
                                ),
                                _popupItem(
                                  value: 'size_asc',
                                  icon: Icons.straighten_outlined,
                                  label: "${'size'.tr} ↑",
                                  selected: ctrl.sortMode.value == 'size_asc',
                                ),
                                _popupItem(
                                  value: 'size_desc',
                                  icon: Icons.straighten_outlined,
                                  label: "${'size'.tr} ↓",
                                  selected: ctrl.sortMode.value == 'size_desc',
                                ),
                                _popupItem(
                                  value: 'type_asc',
                                  icon: Icons.category_outlined,
                                  label: "${'type'.tr} ↑",
                                  selected: ctrl.sortMode.value == 'type_asc',
                                ),
                                _popupItem(
                                  value: 'type_desc',
                                  icon: Icons.category_outlined,
                                  label: "${'type'.tr} ↓",
                                  selected: ctrl.sortMode.value == 'type_desc',
                                ),
                                _popupItem(
                                  value: 'mtime_asc',
                                  icon: Icons.schedule_outlined,
                                  label: "${'folder_sort_mtime'.tr} ↑",
                                  selected: ctrl.sortMode.value == 'mtime_asc',
                                ),
                                _popupItem(
                                  value: 'mtime_desc',
                                  icon: Icons.schedule_outlined,
                                  label: "${'folder_sort_mtime'.tr} ↓",
                                  selected: ctrl.sortMode.value == 'mtime_desc',
                                ),
                              ],
                            );
                        if (result != null) ctrl.setSortMode(result);
                      },
                    ),
                  ),
                ),
              ),
            if (!isRecent) const SizedBox(width: 4),
            // 视图
            if (!isRecent)
              IgnorePointer(
                ignoring: hoverMenusDisabled,
                child: Obx(() {
                  final mode = ctrl.viewMode.value;
                  final tooltip = mode == 'list'
                      ? 'folder_view_list'.tr
                      : mode == 'large_grid'
                      ? 'folder_view_large_grid'.tr
                      : 'folder_view_grid'.tr;
                  return CustomBorderedIconButton(
                    tooltip: tooltip,
                    icon: mode == 'list'
                        ? Icons.view_list_outlined
                        : mode == 'large_grid'
                        ? Icons.grid_view_outlined
                        : Icons.grid_on_outlined,
                    onTap: () {
                      final next = mode == 'grid'
                          ? 'large_grid'
                          : mode == 'large_grid'
                          ? 'list'
                          : 'grid';
                      ctrl.toggleViewMode(next);
                    },
                  );
                }),
              ),
            if (!isRecent && !searching) const SizedBox(width: 4),
            // 筛选
            if (!isRecent && !searching)
              IgnorePointer(
                ignoring: hoverMenusDisabled,
                child: Padding(
                  key: _filterKey,
                  padding: EdgeInsets.zero,
                  child: Obx(
                    () => CustomBorderedIconButton(
                      tooltip: 'filter'.tr,
                      icon: Icons.filter_alt_outlined,
                      active: ctrl.filterType.value != 'all',
                      onTap: () async {
                        final result =
                            await PopupMenuUtil.showBelowButton<String>(
                              context: context,
                              buttonKey: _filterKey,
                              items: [
                                _popupItem(
                                  value: 'all',
                                  icon: Icons.filter_alt_outlined,
                                  label: 'all'.tr,
                                ),
                                _popupItem(
                                  value: 'dir',
                                  icon: Icons.folder_open_outlined,
                                  label: 'dir'.tr,
                                ),
                                _popupItem(
                                  value: 'document',
                                  icon: Icons.description_outlined,
                                  label: 'folder_filter_document'.tr,
                                ),
                                _popupItem(
                                  value: 'video',
                                  icon: Icons.videocam_outlined,
                                  label: 'folder_filter_video'.tr,
                                ),
                                _popupItem(
                                  value: 'audio',
                                  icon: Icons.audiotrack_outlined,
                                  label: 'folder_filter_audio'.tr,
                                ),
                                _popupItem(
                                  value: 'image',
                                  icon: Icons.image_outlined,
                                  label: 'folder_filter_image'.tr,
                                ),
                                _popupItem(
                                  value: 'archive',
                                  icon: Icons.archive_outlined,
                                  label: 'folder_filter_archive'.tr,
                                ),
                                _popupItem(
                                  value: 'file',
                                  icon: Icons.insert_drive_file_outlined,
                                  label: 'file'.tr,
                                ),
                              ],
                            );
                        if (result != null) ctrl.setFilterType(result);
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  PopupMenuItem<String> _popupItem({
    required String value,
    required IconData icon,
    required String label,
    bool selected = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: selected ? const Icon(Icons.check, size: 18) : null,
          ),
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Future<String?> _inputDialog(BuildContext context, String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return DialogUtil.createAlertDialog(
          title: Text(title),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _inputFileDialog(
    BuildContext context, {
    required String title,
    required String ext,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return DialogUtil.createAlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(suffixText: ext),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  Navigator.pop(ctx, null);
                  return;
                }
                final normalized = raw.toLowerCase().endsWith(ext.toLowerCase())
                    ? raw
                    : '$raw$ext';
                Navigator.pop(ctx, normalized);
              },
              child: Text('ok'.tr),
            ),
          ],
        );
      },
    );
  }
}
