import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/music_list_controller.dart';
import './music_list_item.dart';

class MusicListGrid extends StatelessWidget {
  final MusicListController controller;
  const MusicListGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.crossAxisExtent;
        final desiredWidth = 115.0;
        final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 10);
        final spacing = 4.0;
        final totalSpacing = spacing * (crossAxisCount - 1);
        final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
            .floorToDouble();
        final coverSize = itemWidth * 1;
        final estimatedHeight = coverSize + 56;
        final aspectRatio = itemWidth / estimatedHeight;

        return SliverGrid(
          delegate: SliverChildBuilderDelegate((context, idx) {
            final item = controller.items[idx];
            return Obx(() {
              final selectionMode = controller.isMultiSelectMode.value;
              final selected = controller.selectedItems.contains(item.id);
              return MusicItemCard(
                key: ValueKey('music_item_${item.id}'),
                controller: controller,
                item: item,
                width: itemWidth,
                coverSize: coverSize,
                selectionMode: selectionMode,
                selected: selected,
                onToggleSelected: () => controller.toggleSelection(item.id),
              );
            });
          }, childCount: controller.items.length),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
        );
      },
    );
  }
}

class MusicListFooter extends StatelessWidget {
  final MusicListController controller;
  const MusicListFooter({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loadingMore.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Center(
          child: Text(
            'music_list_no_more'.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }

      if (!controller.autoLoadFailed.value) {
        return const SizedBox.shrink();
      }

      return Center(
        child: OutlinedButton(
          onPressed: () =>
              controller.loadMore(fromAuto: false).catchError((_) {}),
          child: Text('music_list_load_more'.tr),
        ),
      );
    });
  }
}
