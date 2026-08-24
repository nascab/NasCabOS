import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../models/photo_timeline_model.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../utils/browse_path_utils.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../home/views/pc_home_controller.dart';
import '../../../../files/service/file_api_service.dart';
import '../../../../../core/api/api_controller.dart';
import 'package:path/path.dart' as p;
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/file_util.dart';

/// 时间轴「文件浏览」：优先完整路径，解析为目录（含 Windows 远端路径与图片/实况后缀）。
String _photoTimelineBrowseFolder(TimelinePhotoItem item) {
  final full = item.fullpath.trim();
  if (full.isNotEmpty) {
    return browseFolderPathPhoto(full);
  }
  final dir = item.path.trim();
  final name = item.filename.trim();
  if (dir.isNotEmpty && name.isNotEmpty) {
    return browseFolderPathPhoto(p.join(dir, name));
  }
  if (dir.isNotEmpty) {
    return browseFolderPathPhoto(dir);
  }
  return '';
}

class PhotoTimelineContextMenu extends StatelessWidget {
  final Widget child;
  final TimelinePhotoItem item;
  final String? controllerTag;

  const PhotoTimelineContextMenu({
    super.key,
    required this.child,
    required this.item,
    this.controllerTag,
  });

  Future<void> _showFileProperties(PhotoTimelineController controller) async {
    try {
      final data = await controller.getFileProperties(item.fullpath);
      if (data != null) {
        showDialog(
          context: Get.overlayContext!,
          builder: (BuildContext context) {
            return DialogUtil.createAlertDialog(
              title: Text('property'.tr),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPropertyRow('location'.tr, data['path'] ?? ''),
                    _buildPropertyRow('file_name'.tr, data['name'] ?? ''),
                    _buildPropertyRow(
                      'total_size'.tr,
                      FileUtil.formatSize(data['size'] ?? 0),
                    ),
                    _buildPropertyRow(
                      'create_time'.tr,
                      data['birthtime'] != null
                          ? controller.formatDateTime(data['birthtime'].toInt())
                          : '',
                    ),
                    _buildPropertyRow(
                      'modified_at'.tr,
                      data['mtime'] != null
                          ? controller.formatDateTime(data['mtime'].toInt())
                          : '',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('confirm'.tr),
                ),
              ],
            );
          },
        );
        return;
      }
    } catch (_) {}

    DialogUtil.showInfoDialog(
      title: 'error'.tr,
      content: 'get_file_property_failed'.tr,
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceUtils.isDesktopOrWeb) return child;
    final controller = Get.find<PhotoTimelineController>(tag: controllerTag);

    return Obx(() {
      final isMulti = controller.isMultiSelectMode.value;
      if (isMulti) {
        return ContextMenuUtil.region(
          child: child,
          entries: const <ContextMenuEntry>[],
        );
      }

      final canSetFaceCover =
          controller.faceId.value != null &&
          CurrentUserController.instance.isAdmin;
      final canShowPhotoFaces = controller.faceId.value != null;
      final canMoveToOtherFace =
          controller.faceId.value != null &&
          CurrentUserController.instance.isAdmin;
      final canRemoveFromFaceAlbum =
          controller.faceId.value != null &&
          CurrentUserController.instance.isAdmin;
      final canSetAlbumCover = controller.albumId.value != null;

      final entries = <ContextMenuEntry>[
        CustomContextMenuItem.create(
          label: Text('open'.tr),
          icon: const Icon(Icons.open_in_new, size: 18),
          value: 'open',
          onSelected: (_) =>
              controller.openMedia(item, controllerTag: controllerTag),
        ),
        const MenuDivider(),
        // 文件浏览：在文件管理器中打开所在目录
        CustomContextMenuItem.create(
          label: Text('file_browse'.tr),
          icon: const Icon(Icons.folder_open, size: 18),
          value: 'file_browse',
          onSelected: (_) {
            final path = _photoTimelineBrowseFolder(item);
            if (path.isEmpty) {
              ToastUtil.show('path_no_set'.tr);
              return;
            }

            if (DeviceUtils.isDesktop) {
              PcHomeController.instance.openFolderAt(path);
            } else {
              AppRoutes.toFiles(initialPath: path);
            }
          },
        ),
        if (canShowPhotoFaces)
          CustomContextMenuItem.create(
            label: Text('face_show_photo_faces'.tr),
            icon: const Icon(Icons.tag_faces_outlined, size: 18),
            value: 'face_show_photo_faces',
            onSelected: (_) => controller.showPhotoDetectedFaces(item),
          ),
        if (canMoveToOtherFace)
          CustomContextMenuItem.create(
            label: Text('face_move_to_other_face'.tr),
            icon: const Icon(Icons.move_down_outlined, size: 18),
            value: 'face_move_to_other_face',
            onSelected: (_) => controller.moveItemToOtherFace(item),
          ),
        if (canSetFaceCover)
          CustomContextMenuItem.create(
            label: Text('face_set_cover'.tr),
            icon: const Icon(Icons.account_circle_outlined, size: 18),
            value: 'face_set_cover',
            onSelected: (_) => controller.setFaceCoverItem(item),
          ),
        if (canSetAlbumCover)
          CustomContextMenuItem.create(
            label: Text('album_set_cover'.tr),
            icon: const Icon(Icons.photo_outlined, size: 18),
            value: 'album_set_cover',
            onSelected: (_) => controller.setAlbumCoverItem(item),
          ),
        const MenuDivider(),
        CustomContextMenuItem.create(
          label: Text(item.isFavorite ? 'unfavorite'.tr : 'favorites'.tr),
          icon: Icon(
            item.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: item.isFavorite ? Colors.red : null,
          ),
          value: 'favorite',
          onSelected: (_) => controller.toggleFavorite(item),
        ),
        CustomContextMenuItem.create(
          label: Text('download'.tr),
          icon: const Icon(Icons.download, size: 18),
          value: 'download',
          onSelected: (_) => controller.downloadItem(item),
        ),
        CustomContextMenuItem.create(
          label: Text('add_to_album'.tr),
          icon: const Icon(Icons.playlist_add, size: 18),
          value: 'add_to_album',
          onSelected: (_) => controller.addToAlbumItem(item),
        ),
        if (controller.albumId.value != null)
          CustomContextMenuItem.create(
            label: Text('remove_from_album'.tr),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            value: 'remove_from_album',
            onSelected: (_) => controller.removeFromAlbumItem(item),
          )
        else if (canRemoveFromFaceAlbum)
          CustomContextMenuItem.create(
            label: Text('face_remove_from_album'.tr),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            value: 'face_remove_from_album',
            onSelected: (_) => controller.removeFromFaceAlbumItem(item),
          ),
        const MenuDivider(),
        CustomContextMenuItem.create(
          color: Colors.red,
          label: Text('delete'.tr),
          icon: const Icon(Icons.delete_outline, size: 18),
          value: 'delete',
          onSelected: (_) => controller.confirmDeleteItem(item),
        ),
        const MenuDivider(),
        // 本机文件系统操作（仅桌面/Web端且客户端与服务端同机时显示）
        if (ApiController.instance.isSameMachine) ...[
          CustomContextMenuItem.create(
            label: Text('file_show_in_folder'.tr),
            icon: const Icon(Icons.folder_open, size: 18),
            value: 'show_in_system',
            onSelected: (_) async {
              if (!ApiController.instance.isServerVersionAtLeast(8)) {
                DialogUtil.showInfoDialog(
                  title: 'tip'.tr,
                  content: 'server_version_too_low'.tr,
                );
                return;
              }
              final path = item.fullpath.trim();
              if (path.isEmpty) return;
              final res = await FileApiService.instance.showInSystem(path);
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
              }
            },
          ),
          CustomContextMenuItem.create(
            label: Text('file_open_in_system'.tr),
            icon: const Icon(Icons.launch, size: 18),
            value: 'open_in_system',
            onSelected: (_) async {
              if (!ApiController.instance.isServerVersionAtLeast(8)) {
                DialogUtil.showInfoDialog(
                  title: 'tip'.tr,
                  content: 'server_version_too_low'.tr,
                );
                return;
              }
              final path = item.fullpath.trim();
              if (path.isEmpty) return;
              final res = await FileApiService.instance.openInSystem(path);
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
              }
            },
          ),
        ],
        CustomContextMenuItem.create(
          label: Text('property'.tr),
          icon: const Icon(Icons.info_outline, size: 18),
          value: 'properties',
          onSelected: (_) => _showFileProperties(controller),
        ),
      ];

      return ContextMenuUtil.region(child: child, entries: entries);
    });
  }
}
