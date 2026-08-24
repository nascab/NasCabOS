import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_no_data.dart';
import '../../../../base/components/custom_outlined_button.dart';
import '../../controller/ai_faces_controller.dart';
import '../../models/ai_faces_models.dart';
import 'ai_faces_item_card.dart';

class AiFacesGrid extends StatelessWidget {
  final AiFacesController controller;
  const AiFacesGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value && controller.items.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!controller.faceEnabled.value) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'photo_ai_face_disabled'.tr,
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
                  onPressed: controller.enableFaceRecognition,
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
          final crossAxisCount = (width / 150).floor().clamp(3, 10);
          const gridPadding = 16.0;
          const crossAxisSpacing = 12.0;
          const mainAxisSpacing = 12.0;

          final itemWidth =
              (width -
                  gridPadding * 2 -
                  crossAxisSpacing * (crossAxisCount - 1)) /
              crossAxisCount;

          final avatarSize = (itemWidth - 12).clamp(64.0, 108.0);

          final titleStyle = Theme.of(context).textTheme.titleSmall;
          final titleFontSize = titleStyle?.fontSize ?? 14.0;
          final titleLineHeight = (titleStyle?.height ?? 1.2) * titleFontSize;

          final bodyStyle = Theme.of(context).textTheme.bodySmall;
          final bodyFontSize = bodyStyle?.fontSize ?? 12.0;
          final bodyLineHeight = (bodyStyle?.height ?? 1.2) * bodyFontSize;

          const verticalPadding = 12.0;
          const gapAfterAvatar = 6.0;
          const gapBeforeCount = 2.0;
          const layoutSafetyBuffer = 4.0;

          final nameAreaHeight = titleLineHeight + 8;
          final countAreaHeight = bodyLineHeight;
          final itemHeight =
              verticalPadding +
              avatarSize +
              gapAfterAvatar +
              nameAreaHeight +
              gapBeforeCount +
              countAreaHeight +
              layoutSafetyBuffer;

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
                    final AiFaceItem face = controller.items[index];
                    return AiFacesItemCard(
                      face: face,
                      controller: controller,
                      avatarSize: avatarSize,
                      onOpen: () => controller.openFace(context, face),
                    );
                  }, childCount: controller.items.length),
                ),
              ),
              SliverToBoxAdapter(
                child: Obx(() {
                  if (!controller.hasMore.value &&
                      !controller.isLoading.value) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: controller.isLoading.value
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: CustomOutlinedButton(
                                  compact: false,
                                  text: 'load_more'.tr,
                                  onPressed: controller.loadMore,
                                ),
                              ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      );
    });
  }
}
