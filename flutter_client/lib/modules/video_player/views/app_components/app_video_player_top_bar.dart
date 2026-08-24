import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/device_utils.dart';
import '../../controllers/video_player_controller.dart';
import '../components/video_info_drawer.dart';

class AppVideoPlayerTopBar extends GetView<PlayerController> {
  const AppVideoPlayerTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: controller.showControls.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: kToolbarHeight + MediaQuery.of(context).padding.top,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () async {
                    await controller.prepareExitIfLandscape();
                    Get.back();
                  },
                ),
                Expanded(
                  child: Obx(() {
                    if (controller.playlist.isEmpty) return const Text('');
                    final item =
                        controller.playlist[controller.currentIndex.value];
                    return Text(
                      item['name'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ),
                if (!DeviceUtils.isMobile)
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
