import 'dart:async';
import 'package:flutter/material.dart';

class VideoHorizontalScroller extends StatefulWidget {
  final List<Widget> children;
  final double height;
  final double sideHintWidth;
  final double scrollStep;

  const VideoHorizontalScroller({
    super.key,
    required this.children,
    required this.height,
    this.sideHintWidth = 44,
    this.scrollStep = 320,
  });

  @override
  State<VideoHorizontalScroller> createState() =>
      _VideoHorizontalScrollerState();
}

class _VideoHorizontalScrollerState extends State<VideoHorizontalScroller> {
  final ScrollController _controller = ScrollController();
  bool _hovering = false;
  bool _hoverLeft = false;
  bool _hoverRight = false;
  bool _scrollable = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  Timer? _throttle;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void didUpdateWidget(covariant VideoHorizontalScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _throttle?.cancel();
    _controller.removeListener(_updateScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted) return;
    if (!_controller.hasClients) {
      if (_scrollable || _canScrollLeft || _canScrollRight) {
        setState(() {
          _scrollable = false;
          _canScrollLeft = false;
          _canScrollRight = false;
        });
      }
      return;
    }

    final pos = _controller.position;
    const eps = 0.5;
    final scrollable = pos.maxScrollExtent - pos.minScrollExtent > eps;
    final canLeft = scrollable && pos.pixels > pos.minScrollExtent + eps;
    final canRight = scrollable && pos.pixels < pos.maxScrollExtent - eps;

    if (scrollable == _scrollable &&
        canLeft == _canScrollLeft &&
        canRight == _canScrollRight) {
      return;
    }
    setState(() {
      _scrollable = scrollable;
      _canScrollLeft = canLeft;
      _canScrollRight = canRight;
    });
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scheduleScroll(double delta) {
    _throttle?.cancel();
    _throttle = Timer(const Duration(milliseconds: 60), () => _scrollBy(delta));
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Colors.white.withOpacity(0.55);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: widget.children,
              ),
            ),
            if (_hovering && _scrollable) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: _canScrollLeft
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hoverLeft = true),
                        onExit: (_) => setState(() => _hoverLeft = false),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _scheduleScroll(-widget.scrollStep),
                            child: Ink(
                              width: widget.sideHintWidth,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.black.withValues(
                                      alpha: _hoverLeft ? 0.42 : 0.30,
                                    ),
                                    Colors.black.withValues(alpha: 0.0),
                                  ],
                                ),
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(16),
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.chevron_left,
                                  color: iconColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _canScrollRight
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _hoverRight = true),
                        onExit: (_) => setState(() => _hoverRight = false),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _scheduleScroll(widget.scrollStep),
                            child: Ink(
                              width: widget.sideHintWidth,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerRight,
                                  end: Alignment.centerLeft,
                                  colors: [
                                    Colors.black.withValues(
                                      alpha: _hoverRight ? 0.42 : 0.30,
                                    ),
                                    Colors.black.withValues(alpha: 0.0),
                                  ],
                                ),
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(16),
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.chevron_right,
                                  color: iconColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
