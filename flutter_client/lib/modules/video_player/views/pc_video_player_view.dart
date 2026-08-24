import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/video_player_controller.dart';
import '../playback/playback_video_surface.dart';
import 'components/web_subtitle_overlay.dart';
import 'pc_components/pc_video_player_top_bar.dart';
import 'pc_components/pc_video_player_bottom_bar.dart';

class PcVideoPlayerView extends StatefulWidget {
  final List<Map<String, dynamic>>? playlist;
  final int initialIndex;

  const PcVideoPlayerView({super.key, this.playlist, this.initialIndex = 0});

  @override
  State<PcVideoPlayerView> createState() => _PcVideoPlayerViewState();
}

class _PcVideoPlayerViewState extends State<PcVideoPlayerView> {
  late final PlayerController controller;
  bool _isControllerCreated = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    if (Get.isRegistered<PlayerController>()) {
      Get.delete<PlayerController>(force: true);
    }
    controller = PlayerController();
    Get.put(controller);
    _isControllerCreated = true;

    final args = Get.arguments as Map<String, dynamic>?;
    final playlist =
        widget.playlist ?? args?['playlist'] as List<Map<String, dynamic>>?;
    final initialIndex = widget.playlist != null
        ? widget.initialIndex
        : (args?['initialIndex'] as int?) ?? 0;
    if (args != null) {
      final raw = args['ignoreFindSub'];
      final parsed = raw == null ? null : int.tryParse(raw.toString());
      controller.ignoreFindSub = (parsed == 0) ? 0 : 1;
    } else {
      controller.ignoreFindSub = 1;
    }

    int? maxRetryFromArgs;
    if (args != null) {
      final raw = args['maxRetryCount'] ?? args['maxReloadRetries'];
      if (raw != null) {
        final parsed = int.tryParse(raw.toString());
        if (parsed != null && parsed >= 0) {
          maxRetryFromArgs = parsed;
        }
      }
    }

    if (playlist != null && playlist.isNotEmpty) {
      controller.openPlaylist(
        items: playlist,
        initialIndex: initialIndex,
        maxRetryCount: maxRetryFromArgs,
      );
    }
  }

  @override
  void dispose() {
    if (_isControllerCreated && Get.isRegistered<PlayerController>()) {
      Get.delete<PlayerController>(force: true);
    }
    super.dispose();
  }

  void _closePlayer() {
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            controller.rewind(seconds: 10);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            controller.fastForward(seconds: 30);
          } else if (event.logicalKey == LogicalKeyboardKey.space) {
            controller.togglePlay();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            // 全屏时先退出全屏，再按一次才关闭播放器
            if (controller.isFullscreen.value) {
              controller.exitFullscreen();
            } else {
              _closePlayer();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
              event.logicalKey == LogicalKeyboardKey.controlRight) {
            controller.setCtrlSpeedBoost(true);
          } else if (event.logicalKey == LogicalKeyboardKey.minus ||
              event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
            controller.decreaseVolume();
          } else if (event.logicalKey == LogicalKeyboardKey.equal ||
              event.logicalKey == LogicalKeyboardKey.add ||
              event.logicalKey == LogicalKeyboardKey.numpadAdd) {
            controller.increaseVolume();
          }
        } else if (event is KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
              event.logicalKey == LogicalKeyboardKey.controlRight) {
            controller.setCtrlSpeedBoost(false);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => controller.onMouseHover(),
          child: Stack(
            children: [
              Positioned.fill(
                child: Obx(() {
                  final engine = controller.playbackEngine.value;
                  if (engine == null || !controller.shouldMountVideoSurface) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      PlaybackVideoSurface(
                        engine: engine,
                        onNativeViewCreated: controller.onMedia3SurfaceReady,
                        onSurfaceTap: controller.handlePlayerTap,
                      ),
                      if (!controller.isInitialized.value)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  );
                }),
              ),
              Positioned.fill(
                child: Obx(
                  () => WebSubtitleOverlay(
                    text: controller.webActiveSubtitleText.value,
                  ),
                ),
              ),
              const PcVideoPlayerTopBar(),
              const PcVideoPlayerBottomBar(),
              Obx(() {
                if (!controller.isCtrlSpeedBoost.value) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: 42,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          'player_speed_boost_tip'.tr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
