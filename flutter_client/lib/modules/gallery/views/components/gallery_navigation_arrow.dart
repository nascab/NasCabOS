import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/custom_gallery_controller.dart';

/// 画廊导航箭头组件
class GalleryNavigationArrow extends StatelessWidget {
  const GalleryNavigationArrow({super.key, required this.isLeft});

  /// 是否为左箭头
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CustomGalleryController>();
    final screenWidth = MediaQuery.of(context).size.width;

    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: screenWidth * 0.2,
      child: GestureDetector(
        onTap: () =>
            isLeft ? controller.previousImage() : controller.nextImage(),
        child: Obx(() {
          // 箭头始终显示，与其他控件同步
          return AnimatedOpacity(
            opacity: controller.isControlsVisible.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            // 箭头定位在侧边，而不是中央
            child: Align(
              alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: isLeft
                    ? const EdgeInsets.only(left: 20)
                    : const EdgeInsets.only(right: 20),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    isLeft ? Icons.chevron_left : Icons.chevron_right,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
