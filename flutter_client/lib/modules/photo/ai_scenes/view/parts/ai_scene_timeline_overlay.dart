import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../timeline/view/pc_photo_timeline.dart';
import '../../controller/ai_scenes_controller.dart';
import '../../models/ai_scenes_models.dart';

class AiSceneTimelineOverlay extends StatelessWidget {
  final AiScenesController controller;
  const AiSceneTimelineOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final AiSceneItem? scene = controller.activeScene.value;
      if (scene == null) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final name = scene.placeName.trim();
      final displayName = name.isNotEmpty ? name : 'scene_unnamed'.tr;
      const avatarSize = 34.0;
      final coverPath = scene.cover?.fullpath.trim() ?? '';
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
                        onPressed: controller.closeScene,
                        icon: const Icon(Icons.close),
                      ),
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.08,
                            ),
                          ),
                        ),
                        child: ClipOval(
                          child: coverPath.isEmpty
                              ? Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.landscape_outlined,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    size: 18,
                                  ),
                                )
                              : CustomExtendedImage(
                                  cache: false,
                                  imageUrl: ApiController.instance.getTinyUrl(
                                    coverPath,
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
                          displayName,
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
                    key: ValueKey('scene_timeline_${scene.placeNameRaw}'),
                    listType: 'timeline',
                    placeName: scene.placeNameRaw,
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
