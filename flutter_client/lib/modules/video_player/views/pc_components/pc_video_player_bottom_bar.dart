import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';
import '../app_components/app_video_menus.dart';
import 'pc_video_volume_control.dart';
import 'pc_video_playlist_dialog.dart';
import '../../../base/components/custom_icon_button.dart';

/// 与下方 [SliderTheme] 的 thumb / overlay 一致。Material [BaseSliderTrackShape] 在
/// `SliderThemeData.padding == null` 时，轨道相对 Slider 左右各缩进
/// `max(overlay 宽/2, thumb 宽/2)`，即 `max(overlayRadius, thumbRadius)`。
const double _pcSliderThumbRadius = 6;
const double _pcSliderOverlayRadius = 10;
const double _pcSliderTrackHorizontalInset =
    _pcSliderOverlayRadius > _pcSliderThumbRadius
    ? _pcSliderOverlayRadius
    : _pcSliderThumbRadius;

class PcVideoPlayerBottomBar extends GetView<PlayerController> {
  const PcVideoPlayerBottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: controller.showControls.value ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MouseRegion(
            // 当鼠标在控制栏上时，保持显示
            onEnter: (_) => controller.showControls.value = true,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 进度条上方：左侧当前/总时长，右侧恢复播放倒计时（窄屏时倒计时优先，挤压左侧时长）
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 4,
                      left: _pcSliderTrackHorizontalInset,
                      right: _pcSliderTrackHorizontalInset,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Obx(
                              () => Text(
                                '${_formatDuration(controller.position.value)} / ${_formatDuration(controller.duration.value)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                        Flexible(
                          flex: 0,
                          fit: FlexFit.loose,
                          child: Obx(() {
                            final count = controller.resumeTipCountdown.value;
                            if (count <= 0) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: controller.onResumeTipTap,
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          color: Colors.blueAccent,
                                          fontSize: 12,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'player_resume_tip'.tr,
                                          ),
                                          const TextSpan(text: ' '),
                                          TextSpan(text: '$count s'),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  // 进度条
                  SizedBox(
                    height: 20,
                    child: Obx(() {
                      final duration = controller.duration.value.inMilliseconds
                          .toDouble();
                      final position = controller.position.value.inMilliseconds
                          .toDouble();
                      final maxVal = duration > 0 ? duration : 1.0;
                      final val = position.clamp(0.0, maxVal);
                      return SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: _pcSliderThumbRadius,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: _pcSliderOverlayRadius,
                          ),
                          activeTrackColor: Colors.blueAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.blueAccent,
                        ),
                        child: Slider(
                          value: val,
                          min: 0,
                          max: maxVal,
                          onChanged: (v) {
                            controller.seekTo(
                              Duration(milliseconds: v.toInt()),
                            );
                          },
                        ),
                      );
                    }),
                  ),
                  // 按钮区域
                  Row(
                    children: [
                      IconButton(
                        icon: Obx(
                          () => Icon(
                            controller.isPlaying.value
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
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
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: controller.playNext,
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        onPressed: () => controller.rewind(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_30, color: Colors.white),
                        onPressed: () => controller.fastForward(),
                      ),
                      IconButton(
                        tooltip: 'player_loop'.tr,
                        icon: Obx(() {
                          final mode = controller.loopMode.value;
                          final IconData icon = switch (mode) {
                            'single' => Icons.repeat_one,
                            'all' => Icons.repeat,
                            'shuffle' => Icons.shuffle,
                            _ => Icons.format_list_numbered,
                          };
                          return Icon(icon, color: Colors.white);
                        }),
                        onPressed: () =>
                            AppVideoMenus.showLoopModeMenu(context, controller),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PopupMenuButton<double>(
                                  tooltip: 'player_play_speed'.tr,
                                  itemBuilder: (context) {
                                    final speeds = [
                                      0.5,
                                      0.75,
                                      1.0,
                                      1.25,
                                      1.5,
                                      2.0,
                                    ];
                                    final selected =
                                        controller.playbackSpeed.value;
                                    return speeds
                                        .map(
                                          (s) => CheckedPopupMenuItem<double>(
                                            value: s,
                                            checked: s == selected,
                                            child: Text('${s}x'),
                                          ),
                                        )
                                        .toList();
                                  },
                                  onSelected: (v) {
                                    controller.setSpeed(v);
                                  },
                                  child: Obx(
                                    () => Text(
                                      '${controller.playbackSpeed.value}x',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!controller.isUrlSource.value)
                                  PopupMenuButton<String>(
                                    tooltip: 'player_choose_quality'.tr,
                                    itemBuilder: (context) {
                                      return controller.qualityOptions
                                          .map(
                                            (t) => PopupMenuItem(
                                              value: t,
                                              child: Text(
                                                controller.qualityLabelShort(t),
                                              ),
                                            ),
                                          )
                                          .toList();
                                    },
                                    onSelected: (v) {
                                      controller.changeQuality(v);
                                    },
                                    child: Obx(() {
                                      return Text(
                                        controller.qualityLabelShort(
                                          controller.currentQuality.value,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      );
                                    }),
                                  ),
                                if (!controller.isUrlSource.value)
                                  const SizedBox(width: 8),
                                if (!controller.isUrlSource.value)
                                  IconButton(
                                    tooltip: 'player_choose_subtitle'.tr,
                                    icon: const Icon(
                                      Icons.subtitles,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        AppVideoMenus.showSubtitleMenu(
                                          context,
                                          controller,
                                        ),
                                  ),
                                if (!controller.isUrlSource.value)
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.audiotrack,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'player_choose_audio'.tr,
                                    itemBuilder: (context) {
                                      final tracks =
                                          controller.audioTracks.isEmpty
                                          ? ['default'.tr]
                                          : controller.audioTracks;
                                      final selected =
                                          controller.currentAudioTrack.value;
                                      return tracks
                                          .map(
                                            (t) => CheckedPopupMenuItem(
                                              value: t,
                                              checked:
                                                  selected.isNotEmpty &&
                                                  selected == t,
                                              child: Text(t),
                                            ),
                                          )
                                          .toList();
                                    },
                                    onSelected: (v) =>
                                        controller.setAudioTrack(v),
                                  ),
                                CustomIconButton(
                                  tooltip: 'player_playlist'.tr,
                                  icon: Icons.playlist_play,
                                  iconColor: Colors.white,
                                  onPressed: () =>
                                      PcVideoPlaylistDialog.show(context),
                                ),
                                // IconButton(
                                //   icon: const Icon(
                                //     Icons.settings,
                                //     color: Colors.white,
                                //   ),
                                //   onPressed: () {},
                                // ),
                                PcVideoVolumeControl(controller: controller),
                                IconButton(
                                  icon: Obx(
                                    () => Icon(
                                      controller.isFullscreen.value
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                  onPressed: controller.toggleFullscreen,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
