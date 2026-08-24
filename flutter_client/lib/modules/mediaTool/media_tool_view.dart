import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'media_tool_controller.dart';
import 'media_tool_left_menu.dart';
import '../../utils/device_utils.dart';
import 'app_media_tool_entry_view.dart';
import 'image_compress/view/image_compress_view.dart';
import 'image_compress_batch/view/img_batch_compress_view.dart';
import 'video_trans/view/video_trans_view.dart';
import 'audio_trans/view/audio_trans_view.dart';
import 'media_arrange/view/media_arrange_view.dart';

class MediaToolView extends StatelessWidget {
  const MediaToolView({super.key});

  @override
  Widget build(BuildContext context) {
    if (DeviceUtils.isPhone(context)) {
      return const AppMediaToolEntryView();
    }
    return GetBuilder<MediaToolController>(
      init: MediaToolController(),
      builder: (ctrl) {
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;

          return Scaffold(
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: leftWidth,
                  child: MediaToolLeftMenu(
                    controller: ctrl,
                    collapsed: collapsed,
                    onToggleCollapse: () =>
                        ctrl.sidebarCollapsed.value = !collapsed,
                  ),
                ),
                Expanded(child: _buildRight(ctrl)),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildRight(MediaToolController ctrl) {
    return Obx(() {
      final key = ctrl.currentPageKey.value;
      if (key == 'image.compress') {
        return const ImageCompressView();
      }
      if (key == 'image.batch_compress') {
        return const ImgBatchCompressView();
      }
      if (key == 'video.trans') {
        return const VideoTransView();
      }
      if (key == 'audio.trans') {
        return const AudioTransView();
      }
      if (key == 'other.media_arrange') {
        return const MediaArrangeView();
      }
      return Center(child: Text('not_implemented_yet'.tr));
    });
  }
}
