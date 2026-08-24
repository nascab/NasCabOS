import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';

class PcVideoPlaylistDialog extends GetView<PlayerController> {
  const PcVideoPlaylistDialog({super.key});

  static void show(BuildContext context) {
    Get.dialog(const PcVideoPlaylistDialog(), barrierDismissible: true);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          height: 480,
          margin: const EdgeInsets.only(right: 16, bottom: 110),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.playlist_play, color: Colors.white70),
                    const SizedBox(width: 8),
                    const Text(
                      '播放列表',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: Get.back,
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
              Expanded(
                child: Obx(() {
                  final list = controller.playlist;
                  final current = controller.currentIndex.value;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final name = item['name']?.toString();
                      final path = item['path']?.toString();
                      final title = (name != null && name.isNotEmpty)
                          ? name
                          : (path ?? '');
                      final selected = index == current;

                      return InkWell(
                        onTap: () {
                          Get.back();
                          controller.playAt(index);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          color: selected ? Colors.white12 : Colors.transparent,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: selected
                                    ? const Icon(
                                        Icons.play_arrow,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white60,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
