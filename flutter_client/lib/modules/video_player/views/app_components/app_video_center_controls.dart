import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';

class AppVideoCenterControls extends GetView<PlayerController> {
  const AppVideoCenterControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 中间播放按钮 (仅暂停时显示，或作为指示)
        Obx(() {
          if (controller.isLocked.value) return const SizedBox.shrink();
          if (!controller.showControls.value) return const SizedBox.shrink();
          return Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: IconButton(
              iconSize: 48,
              icon: Icon(
                controller.isPlaying.value ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: controller.togglePlay,
            ),
          );
        }),

        // 锁屏按钮 (左侧)
        Obx(
          () => AnimatedOpacity(
            opacity: controller.showControls.value && !controller.isLocked.value
                ? 1.0
                : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: IconButton(
                  icon: const Icon(Icons.lock_open, color: Colors.white),
                  onPressed: controller.lockScreen,
                ),
              ),
            ),
          ),
        ),

        Obx(() {
          if (!controller.isLocked.value) return const SizedBox.shrink();
          return AnimatedOpacity(
            opacity: controller.showLockedIcon.value ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.white),
                  onPressed: controller.unlockScreen,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
