import 'package:flutter/material.dart';

/// 水平分割视图，可拖动调整左侧宽度
class CustomSplitView extends StatelessWidget {
  final double leftWidth;
  final double minLeftWidth;
  final double maxLeftWidth;
  final Widget left;
  final Widget right;
  final ValueChanged<double> onResize;

  const CustomSplitView({
    super.key,
    required this.leftWidth,
    required this.left,
    required this.right,
    required this.onResize,
    this.minLeftWidth = 120,
    this.maxLeftWidth = 300,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            SizedBox(
              width: leftWidth.clamp(minLeftWidth, maxLeftWidth),
              child: left,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                onResize(leftWidth + d.delta.dx);
              },
              child: SizedBox(
                width: 2,
                height: constraints.maxHeight,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
