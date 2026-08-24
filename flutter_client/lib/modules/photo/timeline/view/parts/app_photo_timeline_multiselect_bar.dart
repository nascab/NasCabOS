import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../models/photo_timeline_model.dart';

class AppPhotoTimelineMultiSelectBottomBar
    extends GetView<PhotoTimelineController> {
  final String controllerTag;
  const AppPhotoTimelineMultiSelectBottomBar({
    super.key,
    required this.controllerTag,
  });

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surface;
    return Obx(() {
      if (!controller.isMultiSelectMode.value) return const SizedBox.shrink();
      final disabled = controller.selectedItems.isEmpty;
      final selectedPhotos = controller.getSelectedPhotoItems();
      final singleSelectedPhoto = selectedPhotos.length == 1
          ? selectedPhotos.first
          : null;
      final isFaceAlbum =
          controller.faceId.value != null &&
          CurrentUserController.instance.isAdmin;
      return Container(
        color: bgColor,
        child: SafeArea(
          top: false,
          child: Container(
            height: 65,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (!isFaceAlbum)
                  _barAction(
                    context,
                    icon: controller.listType.value == 'favorite'
                        ? Icons.favorite_border
                        : Icons.favorite,
                    label: controller.listType.value == 'favorite'
                        ? 'unfavorite'.tr
                        : 'favorites'.tr,
                    enabled: !disabled,
                    onTap: () => controller.favoriteSelected(),
                  ),
                _barAction(
                  context,
                  icon: Icons.download_rounded,
                  label: 'download'.tr,
                  enabled: !disabled,
                  onTap: controller.downloadSelected,
                ),
                if (isFaceAlbum)
                  _barAction(
                    context,
                    icon: Icons.move_down_outlined,
                    label: 'face_move_to_other_face'.tr,
                    enabled: !disabled,
                    onTap: controller.moveSelectedToOtherFace,
                  ),
                if (isFaceAlbum)
                  _barAction(
                    context,
                    icon: Icons.exit_to_app_outlined,
                    label: 'face_remove_from_album'.tr,
                    enabled: !disabled,
                    onTap: controller.removeFromFaceAlbumSelected,
                  ),
                _barAction(
                  context,
                  icon: isFaceAlbum ? Icons.more_horiz : Icons.delete_outline,
                  label: isFaceAlbum ? 'more'.tr : 'delete'.tr,
                  enabled: !disabled,
                  danger: !isFaceAlbum,
                  onTap: () {
                    if (isFaceAlbum) {
                      _showMoreSheet(
                        context,
                        controller,
                        disabled,
                        isFaceAlbum: true,
                        singleSelectedPhoto: singleSelectedPhoto,
                      );
                      return;
                    }
                    controller.deleteSelected();
                  },
                ),
                if (!isFaceAlbum)
                  _barAction(
                    context,
                    icon: Icons.more_horiz,
                    label: 'more'.tr,
                    enabled: !disabled,
                    onTap: () => _showMoreSheet(
                      context,
                      controller,
                      disabled,
                      isFaceAlbum: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  static Widget _barAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: enabled ? color : theme.disabledColor),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: enabled ? color : theme.disabledColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showMoreSheet(
    BuildContext context,
    PhotoTimelineController controller,
    bool disabled, {
    required bool isFaceAlbum,
    TimelinePhotoItem? singleSelectedPhoto,
  }) async {
    if (disabled) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  controller.listType.value == 'favorite'
                      ? Icons.favorite_border
                      : Icons.favorite,
                ),
                title: Text(
                  controller.listType.value == 'favorite'
                      ? 'unfavorite'.tr
                      : 'favorites'.tr,
                ),
                onTap: () async {
                  Get.back();
                  await controller.favoriteSelected();
                },
              ),
              if (isFaceAlbum && singleSelectedPhoto != null)
                ListTile(
                  leading: const Icon(Icons.tag_faces_outlined),
                  title: Text('face_show_photo_faces'.tr),
                  onTap: () async {
                    Get.back();
                    await controller.showPhotoDetectedFaces(
                      singleSelectedPhoto,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: Text('add_to_album'.tr),
                onTap: () async {
                  Get.back();
                  await controller.addToAlbumSelected();
                },
              ),
              if (controller.albumId.value != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: Text('remove_from_album'.tr),
                  onTap: () async {
                    Get.back();
                    await controller.removeFromAlbumSelected();
                  },
                ),
              if (isFaceAlbum)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text('delete'.tr),
                  onTap: () async {
                    Get.back();
                    await controller.deleteSelected();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text('cancel'.tr),
                onTap: () {
                  Get.back();
                  controller.exitMultiSelectMode();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
