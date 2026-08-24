import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../controllers/pc_file_explorer_controller.dart';

/// 列表视图标题栏（可拖动修改列宽、支持排序、全选）
class PcFileListHeader extends StatelessWidget {
  PcFileListHeader({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 35,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              _sortableCell(
                context,
                'name',
                'name'.tr,
                showSelectAll: true,
                minWidth: 120,
              ),
              _sortableCell(
                context,
                'mtime',
                'folder_col_mtime'.tr,
                minWidth: 80,
              ),
              _sortableCell(context, 'size', 'size'.tr, minWidth: 50),
              _sortableCell(
                context,
                'type',
                'type'.tr,
                isLast: true,
                minWidth: 50,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _selectAllBox() {
    return Obx(() {
      // 读取关键依赖，确保Obx订阅
      final all = ctrl.displayItems
          .where((e) => (e['virtualType']?.toString() ?? '').isEmpty)
          .map((e) => e['path'] as String)
          .toSet();
      final selected = ctrl.selected;
      final allSelected = all.isNotEmpty && selected.length == all.length;
      return CustomCheckbox(
        value: allSelected,
        onChanged: (_) {
          if (allSelected) {
            ctrl.clearSelect();
          } else {
            ctrl.selected
              ..clear()
              ..addAll(all);
            ctrl.selected.refresh();
          }
        },
      );
    });
  }

  Widget _sortableCell(
    BuildContext context,
    String key,
    String title, {
    bool isLast = false,
    bool showSelectAll = false,
    int minWidth = 120,
  }) {
    final theme = Theme.of(context);
    return _resizableCell(
      context,
      key,
      isLast: isLast,
      minWidth: minWidth,
      child: Obx(() {
        final isRecent = ctrl.currentModule.value == 'recent';
        return Opacity(
          opacity: isRecent ? 0.6 : 1,
          child: InkWell(
            onTap: isRecent
                ? null
                : () {
                    final mode = ctrl.sortMode.value;
                    String ascKey = '${key}_asc';
                    String descKey = '${key}_desc';
                    if (key == 'name') {
                      ascKey = 'name_asc';
                      descKey = 'name_desc';
                    }
                    if (key == 'size') {
                      ascKey = 'size_asc';
                      descKey = 'size_desc';
                    }
                    if (key == 'type') {
                      ascKey = 'type_asc';
                      descKey = 'type_desc';
                    }
                    if (key == 'mtime') {
                      ascKey = 'mtime_asc';
                      descKey = 'mtime_desc';
                    }
                    if (mode == ascKey) {
                      ctrl.setSortMode(descKey);
                    } else {
                      ctrl.setSortMode(ascKey);
                    }
                  },
            child: Row(
              children: [
                if (showSelectAll) _selectAllBox(),
                if (showSelectAll) const SizedBox(width: 8),
                Text(title, style: theme.textTheme.bodySmall),
                const SizedBox(width: 4),
                Obx(() {
                  final mode = ctrl.sortMode.value;
                  final ascKey = {
                    'name': 'name_asc',
                    'size': 'size_asc',
                    'type': 'type_asc',
                    'mtime': 'mtime_asc',
                  }[key]!;
                  final descKey = {
                    'name': 'name_desc',
                    'size': 'size_desc',
                    'type': 'type_desc',
                    'mtime': 'mtime_desc',
                  }[key]!;
                  if (mode == ascKey) {
                    return const Icon(Icons.arrow_upward, size: 14);
                  } else if (mode == descKey) {
                    return const Icon(Icons.arrow_downward, size: 14);
                  } else {
                    return const SizedBox.shrink();
                  }
                }),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _resizableCell(
    BuildContext context,
    String key, {
    required Widget child,
    bool isLast = false,
    int minWidth = 120,
  }) {
    final theme = Theme.of(context);
    return Obx(() {
      final w = ctrl.columnWidths[key] ?? minWidth.toDouble();
      return SizedBox(
        width: w,
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: child,
                ),
              ),
            ),
            if (!isLast)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) {
                    final nw = (w + d.delta.dx)
                        .clamp(minWidth.toDouble(), 400)
                        .toDouble();
                    ctrl.columnWidths[key] = nw;
                    ctrl.columnWidths.refresh();
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}
