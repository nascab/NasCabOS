import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../timeline/view/pc_photo_timeline.dart';
import '../../controller/ai_faces_controller.dart';
import '../../models/ai_faces_models.dart';

class AiFaceTimelineOverlay extends StatelessWidget {
  final AiFacesController controller;
  const AiFaceTimelineOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final AiFaceItem? face = controller.activeFace.value;
      if (face == null) return const SizedBox.shrink();
      final name = (face.name ?? '').trim();
      final displayName = name.isNotEmpty ? name : '(${'face_unnamed'.tr})';
      const avatarSize = 34.0;
      final customColors = Theme.of(context).extension<CustomColors>();
      return Positioned.fill(
        child: Material(
          color: customColors?.leftTreeBgColor,
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Get.theme.dividerColor),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'back'.tr,
                        onPressed: controller.closeFace,
                        icon: const Icon(Icons.close),
                      ),
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ClipOval(
                          child: CustomExtendedImage(
                            cache: false,
                            imageUrl: ApiController.instance.getFaceImageUrl(
                              faceId: face.faceId,
                              size: 120,
                              quality: 85,
                            ),
                            width: avatarSize,
                            height: avatarSize,
                            fit: BoxFit.cover,
                            borderRadius: avatarSize / 2,
                            showLoading: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "${"photo_menu_ai_face".tr}-$displayName",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Get.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PcPhotoTimelineView(
                    key: ValueKey('face_timeline_${face.faceId}'),
                    listType: 'timeline',
                    faceId: face.faceId,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
