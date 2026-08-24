import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_no_data.dart';
import '../../../../base/components/custom_outlined_button.dart';
import '../../controller/ai_scenes_controller.dart';
import '../../models/ai_scenes_models.dart';
import 'ai_scene_item_card.dart';

class AiScenesGrid extends StatelessWidget {
  final AiScenesController controller;
  const AiScenesGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!controller.placeEnabled.value) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'photo_ai_scene_disabled'.tr,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 160,
                height: 44,
                child: CustomOutlinedButton(
                  compact: false,
                  text: 'photo_ai_enable_now'.tr,
                  onPressed: controller.enableSceneRecognition,
                ),
              ),
            ],
          ),
        );
      }
      if (controller.items.isEmpty) {
        return CustomNoData(
          text: 'no_data'.tr,
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = (width / 140).floor().clamp(3, 10);
          const gridPadding = 4.0;
          const crossAxisSpacing = 4.0;
          const mainAxisSpacing = 4.0;

          final itemWidth =
              (width -
                  gridPadding * 2 -
                  crossAxisSpacing * (crossAxisCount - 1)) /
              crossAxisCount;

          final avatarSize = (itemWidth).clamp(72.0, 118.0);

          final titleStyle = Theme.of(context).textTheme.titleSmall;
          final titleFontSize = titleStyle?.fontSize ?? 14.0;
          final titleLineHeight = (titleStyle?.height ?? 1.2) * titleFontSize;

          final bodyStyle = Theme.of(context).textTheme.bodySmall;
          final bodyFontSize = bodyStyle?.fontSize ?? 12.0;
          final bodyLineHeight = (bodyStyle?.height ?? 1.2) * bodyFontSize;

          const verticalPadding = 4.0;
          const gapAfterAvatar = 6.0;
          const gapBeforeCount = 2.0;

          final nameAreaHeight = titleLineHeight + 8;
          final countAreaHeight = bodyLineHeight;
          final itemHeight =
              verticalPadding +
              avatarSize +
              gapAfterAvatar +
              nameAreaHeight +
              gapBeforeCount +
              countAreaHeight;

          return CustomScrollView(
            controller: controller.scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(gridPadding),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisSpacing: mainAxisSpacing,
                    mainAxisExtent: itemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final AiSceneItem scene = controller.items[index];
                    return AiSceneItemCard(
                      scene: scene,
                      controller: controller,
                      avatarSize: avatarSize,
                      onOpen: () => controller.openScene(context, scene),
                    );
                  }, childCount: controller.items.length),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}
