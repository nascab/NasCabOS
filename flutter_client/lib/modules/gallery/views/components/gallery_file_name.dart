import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';

/// 画廊底部文件名组件；当为 Live Photo 时可显示 LIVE 标识与播放入口。
class GalleryFileName extends StatelessWidget {
  const GalleryFileName({
    super.key,
    required this.fileName,
    this.isLivePhoto = false,
    this.onLiveTap,
    this.showPanoramaButton = false,
    this.onPanoramaTap,
  });

  /// 文件名称
  final String fileName;

  /// 是否为 Live Photo（is_lvp == 1）
  final bool isLivePhoto;

  /// 点击 Live 播放时回调
  final VoidCallback? onLiveTap;
  final bool showPanoramaButton;
  final VoidCallback? onPanoramaTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: DeviceUtils.isMobile ? 58 : 24,
      left: 0,
      right: 0,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    decoration: TextDecoration.none,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if ((isLivePhoto && onLiveTap != null) ||
                  (showPanoramaButton && onPanoramaTap != null)) ...[
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (isLivePhoto && onLiveTap != null)
                      GestureDetector(
                        onTap: onLiveTap,
                        child: _GalleryActionChip(
                          label: 'LIVE',
                          icon: Icons.play_circle_outline,
                        ),
                      ),
                    if (showPanoramaButton && onPanoramaTap != null)
                      GestureDetector(
                        onTap: onPanoramaTap,
                        child: _GalleryActionChip(
                          label: '360',
                          icon: Icons.threesixty,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryActionChip extends StatelessWidget {
  const _GalleryActionChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.95)),
        ],
      ),
    );
  }
}
