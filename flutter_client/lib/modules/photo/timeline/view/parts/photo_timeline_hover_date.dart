import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/photo_timeline_controller.dart';

class PhotoTimelineHoverDateOverlay extends GetView<PhotoTimelineController> {
  final String? controllerTag;
  const PhotoTimelineHoverDateOverlay({super.key, this.controllerTag});

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Obx(() {
          final visible =
              controller.isTimelineHovering.value &&
              controller.timelineHoverDate.value.isNotEmpty;
          if (!visible) return const SizedBox();

          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                controller.timelineHoverDate.value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
