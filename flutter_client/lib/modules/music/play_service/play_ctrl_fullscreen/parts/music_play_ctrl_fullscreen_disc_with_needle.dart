import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../base/components/custom_extended_image.dart';

class MusicPlayCtrlFullScreenDiscWithNeedle extends StatefulWidget {
  final bool isPlaying;
  final String coverUrl;
  final String discAsset;

  const MusicPlayCtrlFullScreenDiscWithNeedle({
    super.key,
    required this.isPlaying,
    required this.coverUrl,
    required this.discAsset,
  });

  @override
  State<MusicPlayCtrlFullScreenDiscWithNeedle> createState() =>
      _MusicPlayCtrlFullScreenDiscWithNeedleState();
}

class _MusicPlayCtrlFullScreenDiscWithNeedleState
    extends State<MusicPlayCtrlFullScreenDiscWithNeedle>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _needleController;
  late final Animation<double> _needleAngle;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _needleAngle = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _needleController, curve: Curves.easeInOut),
    );
    _sync(widget.isPlaying);
  }

  @override
  void didUpdateWidget(
    covariant MusicPlayCtrlFullScreenDiscWithNeedle oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _sync(widget.isPlaying);
    }
  }

  void _sync(bool playing) {
    if (playing) {
      if (!_rotationController.isAnimating) _rotationController.repeat();
      if (!_needleController.isAnimating) {
        _needleController.repeat(reverse: true);
      }
    } else {
      if (_rotationController.isAnimating) _rotationController.stop();
      if (_needleController.isAnimating) _needleController.stop();
      _needleController.animateTo(
        0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _needleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cover() {
      if (widget.coverUrl.trim().isEmpty) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
        );
      }
      return CustomExtendedImage(
        imageUrl: widget.coverUrl,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, c) {
        final size = min(c.maxWidth, c.maxHeight);
        final discSize = size * 0.9;
        final discLeft = (size - discSize) / 2;
        final inner = (discSize * 0.42 * 1.3).clamp(0.0, discSize * 0.62);
        final needleW = size * 0.42;
        final needleH = size * 0.42;
        const frostedExtraRadius = 10.0;
        final frostedSize = discSize + frostedExtraRadius * 2;
        final frostedLeft = discLeft - frostedExtraRadius;
        final frostedTop = 10 - frostedExtraRadius;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: frostedLeft,
              top: frostedTop,
              width: frostedSize,
              height: frostedSize,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: discLeft,
              top: 10,
              width: discSize,
              height: discSize,
              child: RotationTransition(
                turns: _rotationController,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(widget.discAsset, fit: BoxFit.cover),
                    Center(
                      child: SizedBox(
                        width: inner,
                        height: inner,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 3,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: ClipOval(
                              child: Container(
                                color: theme.colorScheme.surfaceVariant
                                    .withValues(alpha: 0.35),
                                child: cover(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: size * 0.18,
              top: -size * 0.2,
              child: AnimatedBuilder(
                animation: _needleAngle,
                builder: (c, _) {
                  const baseAngle = -0.42;
                  const originX = 0.275;
                  const originY = 0.247;
                  const originAlignment = Alignment(
                    originX * 2 - 1,
                    originY * 2 - 1,
                  );
                  final angle =
                      baseAngle + (widget.isPlaying ? _needleAngle.value : 0);

                  return SizedBox(
                    width: needleW,
                    height: needleH,
                    child: Transform.rotate(
                      alignment: originAlignment,
                      angle: angle,
                      child: Image.asset(
                        'assets/music/icons/player_disc_bar.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.topLeft,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
