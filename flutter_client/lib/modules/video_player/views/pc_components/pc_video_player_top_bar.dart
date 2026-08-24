import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';
import '../components/video_info_drawer.dart';

class PcVideoPlayerTopBar extends GetView<PlayerController> {
  const PcVideoPlayerTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: controller.showControls.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: 60,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.play_circle_outline, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Obx(() {
                  if (controller.playlist.isEmpty) return const Text('');
                  final item =
                      controller.playlist[controller.currentIndex.value];
                  return Text(
                    item['name'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  );
                }),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.white),
                tooltip: 'help'.tr,
                onPressed: () {
                  Get.dialog(
                    AlertDialog(
                      title: Text('player_shortcuts_title'.tr),
                      content: Text('player_shortcuts_content'.tr),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: Text('ok'.tr),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (!controller.isUrlSource.value)
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white),
                  onPressed: () {
                    if (controller.playlist.isNotEmpty) {
                      final item =
                          controller.playlist[controller.currentIndex.value];
                      final path = item['path'];
                      if (path != null) {
                        Get.bottomSheet(
                          VideoInfoDrawer(
                            filePath: path.toString(),
                            playerController: controller,
                          ),
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                        );
                      }
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Get.back(),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
