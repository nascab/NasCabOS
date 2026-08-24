import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';

//底部状态栏：显示当前选中的文件数量和总文件数量
class PcFileBottomStatusBar extends StatelessWidget {
  PcFileBottomStatusBar({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final total = ctrl.displayItems.length;
      final selected = ctrl.selected.length;
      final text = selected > 0
          ? 'folder_status_selected'.trParams({
              'selected': '$selected',
              'total': '$total',
            })
          : 'folder_status_total'.trParams({'total': '$total'});
      return Container(
        height: 32,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(text),
      );
    });
  }
}
