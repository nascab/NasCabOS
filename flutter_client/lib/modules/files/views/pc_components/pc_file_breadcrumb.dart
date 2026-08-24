import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import 'pc_internal_drag_item.dart';

class PcFileBreadcrumb extends StatelessWidget {
  const PcFileBreadcrumb({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;

  @override
  Widget build(BuildContext context) {
    final crumbController = ScrollController();
    return Obx(() {
      final segs = ctrl.segments;
      final separator = ctrl.sep.value;
      final List<Widget> children = [];
      children.add(
        TextButton(
          onPressed: () => ctrl.listDirectory('', null),
          child: Text('folder_picker_root'.tr),
        ),
      );
      if (segs.isNotEmpty) {
        children.add(Text(separator));
        final startIndex =
            (segs.isNotEmpty &&
                (segs.first['name']?.toString() ?? '') == separator)
            ? 1
            : 0;
        for (var i = startIndex; i < segs.length; i++) {
          final s = segs[i];
          final segPath = s['path']?.toString() ?? '';
          children.add(
            PcInternalPathSegmentDropTarget(
              ctrl: ctrl,
              segmentPath: segPath,
              child: TextButton(
                onPressed: () => ctrl.navigateTo(segPath),
                child: Text(s['name']?.toString() ?? ''),
              ),
            ),
          );
          if (i < segs.length - 1) children.add(Text(separator));
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (crumbController.hasClients) {
          final max = crumbController.position.maxScrollExtent;
          crumbController.jumpTo(max);
        }
      });
      return SizedBox(
        height: 40,
        child: SingleChildScrollView(
          controller: crumbController,
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      );
    });
  }
}
