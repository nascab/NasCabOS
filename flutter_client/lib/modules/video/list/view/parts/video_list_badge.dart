import 'package:flutter/material.dart';

class VideoListBadge extends StatelessWidget {
  final int count;
  final Widget child;
  const VideoListBadge({super.key, required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final text = count > 99 ? '99+' : count.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -18,
          top: -14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white, height: 1),
            ),
          ),
        ),
      ],
    );
  }
}
