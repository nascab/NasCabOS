import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';
import 'app_video_menus.dart';

class AppVideoPlayerBottomBar extends GetView<PlayerController> {
  const AppVideoPlayerBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: controller.showControls.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Obx(
                        () => Icon(
                          controller.isLandscape.value
                              ? Icons.stay_current_portrait
                              : Icons.stay_current_landscape,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: controller.toggleOrientation,
                    ),
                  ],
                ),
                // 恢复播放提示（倒计时内显示，可点击从头开始）
                Obx(() {
                  final count = controller.resumeTipCountdown.value;
                  if (count <= 0) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: controller.onResumeTipTap,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            'player_resume_tip'.tr,
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$count s',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // 时间与进度条
                Row(
                  children: [
                    Obx(
                      () => Text(
                        _formatDuration(controller.position.value),
                        style: const TextStyle(color: Colors.blueAccent),
                      ),
                    ),
                    Expanded(
                      child: Obx(() {
                        final duration = controller
                            .duration
                            .value
                            .inMilliseconds
                            .toDouble();
                        final position = controller
                            .position
                            .value
                            .inMilliseconds
                            .toDouble();
                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            activeTrackColor: Colors.blueAccent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.blueAccent,
                          ),
                          child: Slider(
                            value: (position > duration) ? duration : position,
                            min: 0,
                            max: duration > 0 ? duration : 1.0,
                            onChanged: (v) {
                              controller.seekTo(
                                Duration(milliseconds: v.toInt()),
                              );
                            },
                          ),
                        );
                      }),
                    ),
                    Obx(
                      () => Text(
                        _formatDuration(controller.duration.value),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                // 底部按钮行（窄屏可横向滚动，避免溢出）
                Obx(() {
                  final isLandscape = controller.isLandscape.value;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            controller.isPlaying.value
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: controller.togglePlay,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
                          ),
                          onPressed: controller.playPrev,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                          ),
                          onPressed: controller.playNext,
                        ),
                        if (isLandscape)
                          IconButton(
                            icon: const Icon(
                              Icons.replay_10,
                              color: Colors.white,
                            ),
                            onPressed: () => controller.rewind(seconds: 10),
                          ),
                        if (isLandscape)
                          IconButton(
                            icon: const Icon(
                              Icons.forward_30,
                              color: Colors.white,
                            ),
                            onPressed: () =>
                                controller.fastForward(seconds: 30),
                          ),
                        TextButton(
                          onPressed: () {
                            AppVideoMenus.showSpeedMenu(context, controller);
                          },
                          child: Text(
                            '${controller.playbackSpeed.value}x',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (!controller.isUrlSource.value)
                          TextButton(
                            onPressed: () {
                              AppVideoMenus.showQualityMenu(
                                context,
                                controller,
                              );
                            },
                            child: Text(
                              _formatQuality(controller.currentQuality.value),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        if (isLandscape && !controller.isUrlSource.value)
                          IconButton(
                            icon: const Icon(
                              Icons.subtitles,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              AppVideoMenus.showSubtitleMenu(
                                context,
                                controller,
                              );
                            },
                          ),
                        if (isLandscape && !controller.isUrlSource.value)
                          IconButton(
                            icon: const Icon(
                              Icons.audiotrack,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              AppVideoMenus.showAudioMenu(context, controller);
                            },
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.more_horiz,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            AppVideoMenus.showMoreMenu(context, controller);
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatQuality(String quality) {
    return controller.qualityLabelShort(quality);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
