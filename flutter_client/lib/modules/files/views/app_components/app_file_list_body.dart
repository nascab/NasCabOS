import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_divider.dart';
import '../../../base/components/custom_empty_state.dart';
import '../../controllers/app_file_controller.dart';
import 'app_file_items.dart';

class AppFileListBody extends StatelessWidget {
  const AppFileListBody({
    super.key,
    required this.ctrl,
    required this.onOpenDir,
  });

  final AppFileController ctrl;
  final Future<void> Function(String path, String folderName) onOpenDir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      if (ctrl.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final data = ctrl.displayItems;
      if (data.isEmpty) {
        return LayoutBuilder(
          builder: (context, cons) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                SizedBox(
                  height: cons.maxHeight,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: const CustomEmptyState(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }

      final mode = ctrl.viewMode.value;
      // 列表视图
      if (mode == 'list') {
        return Column(
          children: [
            const CustomDivider(height: 1),
            Expanded(
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: data.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.6),
                ),
                itemBuilder: (context, index) {
                  return AppFileListItem(
                    ctrl: ctrl,
                    item: data[index],
                    allItems: data,
                    onOpenDir: onOpenDir,
                  );
                },
              ),
            ),
          ],
        );
      }
      // 网格视图
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isLarge = mode == 'large_grid';
          // 动态计算grid宽和高
          final minItemWidth = isLarge ? 140.0 : 110.0;
          const spacing = 10.0;
          final count = (width + spacing) ~/ (minItemWidth + spacing);
          final crossAxisCount = count > 0 ? count : 1;
          const horizontalPadding = 20.0; // 12(left) + 12(right)
          final itemWidth =
              (width - horizontalPadding - (crossAxisCount - 1) * spacing) /
              crossAxisCount;
          final thumbSize = isLarge ? 128.0 : 80.0;
          final nameStyle = theme.textTheme.bodyMedium;
          final nameLineHeight =
              (nameStyle?.fontSize ?? 14.0) * (nameStyle?.height ?? 1.2);
          const rowHeight = 35.0;
          final desiredHeight =
              (10.0 * 2) + thumbSize + 4.0 + nameLineHeight + 2.0 + rowHeight;
          final childAspectRatio = (itemWidth / desiredHeight).clamp(0.55, 1.4);

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: childAspectRatio, //宽高比
            ),
            itemCount: data.length,
            itemBuilder: (context, index) {
              return AppFileGridItem(
                ctrl: ctrl,
                item: data[index],
                allItems: data,
                large: isLarge,
                onOpenDir: onOpenDir,
              );
            },
          );
        },
      );
    });
  }
}
