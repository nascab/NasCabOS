import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:flutter/material.dart';

class MusicPlayDiscCover extends StatefulWidget {
  final String coverUrl;
  final bool isPlaying;
  final String discAsset;
  final VoidCallback? onTap;
  final double outerSize;
  final double innerSize;
  final Duration rotationDuration;

  const MusicPlayDiscCover({
    super.key,
    required this.coverUrl,
    required this.isPlaying,
    required this.discAsset,
    this.onTap,
    this.outerSize = 58,
    this.innerSize = 40,
    this.rotationDuration = const Duration(seconds: 18),
  });

  @override
  State<MusicPlayDiscCover> createState() => _MusicPlayDiscCoverState();
}

class _MusicPlayDiscCoverState extends State<MusicPlayDiscCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: widget.rotationDuration,
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MusicPlayDiscCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationDuration != widget.rotationDuration) {
      _rotationController.duration = widget.rotationDuration;
    }
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
      return;
    }
    if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outer = widget.outerSize;
    final inner = widget.innerSize;

    Widget cover() {
      if (widget.coverUrl.trim().isEmpty) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          width: inner,
          height: inner,
          fit: BoxFit.cover,
        );
      }
      return CustomExtendedImage(
        imageUrl: widget.coverUrl,
        width: inner,
        height: inner,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/music/icons/default_cover.jpg',
          width: inner,
          height: inner,
          fit: BoxFit.cover,
        ),
      );
    }

    return SizedBox(
      width: outer,
      height: outer,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: RotationTransition(
          turns: _rotationController,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(widget.discAsset, fit: BoxFit.cover),
              Center(
                child: ClipOval(
                  child: Container(
                    width: inner,
                    height: inner,
                    color: theme.colorScheme.surfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    child: cover(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
