import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/book_list_controller.dart';
import '../app_book_sub_list_page.dart';
import 'book_item_card.dart';

class BookListGrid extends StatelessWidget {
  final BookListController controller;
  final bool mobileLayout;
  const BookListGrid({
    super.key,
    required this.controller,
    this.mobileLayout = false,
  });

  static const double _itemScale = 1.7;
  static const double _coverAspectRatio = 3 / 4;
  static const double _titleHeight = 58;
  static const double _titleSpacing = 2;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final coverScale = controller.coverScale.value;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          final baseWidth = (maxWidth < 520 ? 72.0 : 84.0) * _itemScale;
          final desiredWidth = baseWidth * coverScale;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 12);
          final spacing = maxWidth < 520 ? 10.0 : 12.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
              .floorToDouble();
          final coverHeight = itemWidth / _coverAspectRatio;
          final estimatedHeight = coverHeight + _titleSpacing + _titleHeight;
          final aspectRatio = itemWidth / estimatedHeight;

          return SliverGrid(
            delegate: SliverChildBuilderDelegate((context, idx) {
              final item = controller.items[idx];
              return Obx(() {
                final selectionMode = controller.isMultiSelectMode.value;
                final selected = controller.selectedItems.contains(item.id);
                return BookItemCard(
                  key: ValueKey('book_item_${item.id}'),
                  item: item,
                  mobileLayout: mobileLayout,
                  selectionMode: selectionMode,
                  selected: selected,
                  onToggleSelected: () => controller.toggleSelection(item.id),
                  onOpenSeries: () {
                    if (mobileLayout) {
                      Get.to(
                        () => AppBookSubListPage(
                          seriesId: item.id,
                          title: item.displayTitle,
                          type: item.type,
                        ),
                        preventDuplicates: false,
                      );
                    } else {
                      controller.openSeries(item);
                    }
                  },
                  onAddToBookList: () => controller.addToBookListItem(item),
                  onRemoveFromBookList: controller.isInCustomList
                      ? () => controller.removeFromBookListItem(item)
                      : null,
                  onDelete: () => controller.deleteItem(item),
                  onFavoriteChanged: (next) =>
                      controller.updateFavoriteState(item.id, next),
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
    });
  }
}

class BookListFooter extends StatelessWidget {
  final BookListController controller;
  const BookListFooter({super.key, required this.controller});

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
            'book_list_no_more'.tr,
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
          child: Text('book_list_load_more'.tr),
        ),
      );
    });
  }
}
