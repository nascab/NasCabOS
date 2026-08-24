import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../../../../utils/device_utils.dart';

class PhotoTimelineMultiSelectBottomBar
    extends GetView<PhotoTimelineController> {
  final String? controllerTag;
  const PhotoTimelineMultiSelectBottomBar({super.key, this.controllerTag});

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Obx(() {
        if (!controller.isMultiSelectMode.value) return const SizedBox();
        final disabled = controller.selectedItems.isEmpty;
        final applyBottomSafeArea =
            !(DeviceUtils.isDesktop ||
                (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context)));
        final bgColor =
            customColors?.oprationBarBgColor ?? Get.theme.colorScheme.surface;
        return Container(
          color: bgColor,
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: applyBottomSafeArea ? 5 : 0),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  top: BorderSide(
                    color: Get.theme.dividerColor.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${controller.selectedItems.length} ${'selected'.tr}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'download'.tr,
                    onPressed: disabled ? null : controller.downloadSelected,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  Obx(() {
                    final isFavoriteList =
                        controller.listType.value == 'favorite';
                    return IconButton(
                      tooltip: isFavoriteList
                          ? 'unfavorite'.tr
                          : 'favorites'.tr,
                      onPressed: disabled ? null : controller.favoriteSelected,
                      icon: Icon(
                        isFavoriteList
                            ? Icons.favorite_border_outlined
                            : Icons.favorite_rounded,
                      ),
                    );
                  }),
                  IconButton(
                    tooltip: 'add_to_album'.tr,
                    onPressed: disabled ? null : controller.addToAlbumSelected,
                    icon: const Icon(Icons.playlist_add_outlined),
                  ),
                  if (controller.faceId.value != null &&
                      CurrentUserController.instance.isAdmin)
                    IconButton(
                      tooltip: 'face_move_to_other_face'.tr,
                      onPressed: disabled
                          ? null
                          : controller.moveSelectedToOtherFace,
                      icon: const Icon(Icons.move_down_outlined),
                    ),
                  if (controller.albumId.value != null)
                    IconButton(
                      tooltip: 'remove_from_album'.tr,
                      onPressed: disabled
                          ? null
                          : controller.removeFromAlbumSelected,
                      icon: const Icon(Icons.remove_circle_outline_outlined),
                    ),
                  if (controller.faceId.value != null &&
                      CurrentUserController.instance.isAdmin)
                    IconButton(
                      tooltip: 'face_remove_from_album'.tr,
                      onPressed: disabled
                          ? null
                          : controller.removeFromFaceAlbumSelected,
                      icon: const Icon(Icons.exit_to_app_outlined),
                    ),
                  IconButton(
                    tooltip: 'delete'.tr,
                    onPressed: disabled ? null : controller.deleteSelected,
                    icon: Icon(
                      Icons.delete_outline,
                      color: disabled ? null : Colors.red,
                    ),
                  ),
                  IconButton(
                    tooltip: 'cancel'.tr,
                    onPressed: controller.exitMultiSelectMode,
                    icon: const Icon(Icons.close_outlined),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
