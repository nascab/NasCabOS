import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/video_player_controller.dart';

class PcVideoVolumeControl extends StatefulWidget {
  final PlayerController controller;
  const PcVideoVolumeControl({super.key, required this.controller});

  @override
  State<PcVideoVolumeControl> createState() => _PcVideoVolumeControlState();
}

class _PcVideoVolumeControlState extends State<PcVideoVolumeControl> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 40,
        height: 150,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, -160),
          showWhenUnlinked: false,
          child: Material(
            elevation: 8,
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Expanded(
                  child: Obx(
                    () => RotatedBox(
                      quarterTurns: -1,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          activeTrackColor: Colors.blueAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: widget.controller.volume.value,
                          onChanged: widget.controller.setVolume,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(widget.controller.volume.value * 100).toInt()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onExit: (_) {
          // 稍微延迟隐藏，防止滑动时滑出
          // 实际上 Slider 在 overlay 里，这里 exit 只针对按钮
          // 需要更复杂的逻辑或者点击触发
        },
        child: IconButton(
          icon: const Icon(Icons.volume_up, color: Colors.white),
          onPressed: () {
            if (_overlayEntry == null) {
              _showOverlay();
            } else {
              _hideOverlay();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }
}
