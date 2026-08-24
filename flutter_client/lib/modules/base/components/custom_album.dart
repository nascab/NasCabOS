import 'package:flutter/material.dart';

enum CustomAlbumHeaderPosition { top, bottom }

class CustomAlbum extends StatefulWidget {
  final Widget preview;
  final VoidCallback? onTap;

  final Widget? headerLeft;
  final Widget? headerRight;
  final double headerHeight;
  final EdgeInsetsGeometry headerPadding;
  final Gradient? headerGradient;
  final CustomAlbumHeaderPosition headerPosition;

  final List<Widget> overlayChildren;

  final bool hoverEnabled;
  final double hoverScale;
  final Duration hoverDuration;
  final Curve hoverCurve;

  const CustomAlbum({
    super.key,
    required this.preview,
    this.onTap,
    this.headerLeft,
    this.headerRight,
    this.headerHeight = 55,
    this.headerPadding = const EdgeInsets.fromLTRB(10, 0, 2, 0),
    this.headerGradient,
    this.headerPosition = CustomAlbumHeaderPosition.top,
    this.overlayChildren = const [],
    this.hoverEnabled = true,
    this.hoverScale = 1.04,
    this.hoverDuration = const Duration(milliseconds: 200),
    this.hoverCurve = Curves.easeOutCubic,
  });

  @override
  State<CustomAlbum> createState() => _CustomAlbumState();
}

class _CustomAlbumState extends State<CustomAlbum> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hasHeader = widget.headerLeft != null || widget.headerRight != null;

    final defaultGradient =
        widget.headerPosition == CustomAlbumHeaderPosition.top
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.00),
            ],
          )
        : LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.black.withValues(alpha: 0.00),
            ],
          );

    final gradient = widget.headerGradient ?? defaultGradient;

    final header = hasHeader
        ? Positioned(
            left: 0,
            right: 0,
            top: widget.headerPosition == CustomAlbumHeaderPosition.top
                ? 0
                : null,
            bottom: widget.headerPosition == CustomAlbumHeaderPosition.bottom
                ? 0
                : null,
            child: Container(
              height: widget.headerHeight,
              decoration: BoxDecoration(gradient: gradient),
              child: Padding(
                padding: widget.headerPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: widget.headerLeft ?? const SizedBox.shrink(),
                      ),
                    ),
                    if (widget.headerRight != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: widget.headerRight!,
                      ),
                  ],
                ),
              ),
            ),
          )
        : null;

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.preview,
            if (header != null) header,
            ...widget.overlayChildren,
          ],
        ),
      ),
    );

    final effectiveScale = (widget.hoverEnabled && _hovered)
        ? widget.hoverScale
        : 1.0;

    Widget result = AnimatedScale(
      scale: effectiveScale,
      duration: widget.hoverDuration,
      curve: widget.hoverCurve,
      child: card,
    );

    if (widget.hoverEnabled) {
      result = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: result,
      );
    }

    return result;
  }
}
