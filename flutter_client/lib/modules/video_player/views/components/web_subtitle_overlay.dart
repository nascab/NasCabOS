import 'package:flutter/material.dart';

class WebSubtitleOverlay extends StatelessWidget {
  const WebSubtitleOverlay({
    super.key,
    required this.text,
    this.bottomPadding = 88,
  });

  final String text;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final base = (size.shortestSide / 28).clamp(14.0, 28.0);
    final style = TextStyle(
      color: Colors.white,
      fontSize: base,
      height: 1.25,
      shadows: const [
        Shadow(offset: Offset(0, 2), blurRadius: 6, color: Colors.black),
        Shadow(offset: Offset(0, 0), blurRadius: 2, color: Colors.black),
      ],
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
          child: Text(
            t,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ),
    );
  }
}

