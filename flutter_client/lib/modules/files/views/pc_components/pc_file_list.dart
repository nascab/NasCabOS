import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_empty_state.dart';
import 'pc_file_list_gridview.dart';
import 'pc_file_list_listview.dart';
import 'pc_internal_drag_item.dart';
import '../../controllers/pc_file_explorer_controller.dart';

class PcFileList extends StatelessWidget {
  const PcFileList({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = ctrl.viewMode.value;
      final view = (mode == 'grid' || mode == 'large_grid')
          ? PcFileListGridView(ctrl: ctrl)
          : PcFileListListView(ctrl: ctrl);

      final showEmpty = !ctrl.loading.value && ctrl.displayItems.isEmpty;

      final searching = ctrl.searchQuery.value.trim().isNotEmpty;
      final showDragUploadHint =
          ctrl.allowExternalUploadDrop &&
          !searching &&
          ctrl.currentModule.value == 'normal';
      final dropOntoCurrentPath = ctrl.currentModule.value == 'normal' &&
          !ctrl.isRoot &&
          (ctrl.currentPath.value?.trim() ?? '').isNotEmpty;
      Widget listBody = view;
      if (dropOntoCurrentPath) {
        listBody = PcInternalCurrentDirectoryDropTarget(
          ctrl: ctrl,
          child: view,
        );
      }
      if (!showEmpty) return listBody;

      return Stack(
        children: [
          listBody,
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: showDragUploadHint
                      ? _DragUploadEmptyBox(
                          text: 'folder_drag_to_upload_here'.tr,
                        )
                      : const CustomEmptyState(),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _DragUploadEmptyBox extends StatelessWidget {
  const _DragUploadEmptyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor.withValues(alpha: 0.85);
    final boxBg = theme.colorScheme.surface.withValues(alpha: 0.6);

    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: borderColor,
                strokeWidth: 1.2,
                radius: 12,
                dash: 8,
                gap: 6,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 38,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                const SizedBox(height: 10),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dash;
  final double gap;

  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(dash, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius ||
        dash != oldDelegate.dash ||
        gap != oldDelegate.gap;
  }
}
