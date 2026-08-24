import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/device_utils.dart';
import '../../list/controller/book_list_controller.dart';
import '../../list/service/book_list_api_service.dart';
import '../../list/view/parts/book_item_card.dart';
import '../../../base/components/custom_no_data.dart';
import '../controller/book_history_controller.dart';

class BookHistoryListView extends StatelessWidget {
  const BookHistoryListView({super.key});

  @override
  Widget build(BuildContext context) {
    BookListController.ensureSharedCoverScaleLoaded();
    final controller = Get.put(BookHistoryController());
    final isDesktop = DeviceUtils.isDesktopOrWeb;

    return Obx(() {
      if (!controller.firstLoaded.value && controller.loading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.items.isEmpty) {
        return CustomNoData(text: 'no_data'.tr);
      }

      Widget? header;
      if (isDesktop) {
        header = SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                Text(
                  'book_menu_library_history'.tr,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.clearHistory,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('task_clear_all'.tr),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        );
      }

      return CustomScrollView(
        slivers: [
          if (header != null) header,
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _HistoryGrid(items: controller.items),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      );
    });
  }
}

class _HistoryGrid extends StatelessWidget {
  final List<BookListItem> items;
  const _HistoryGrid({required this.items});

  static const double _itemScale = 1.7;
  static const double _coverAspectRatio = 3 / 4;
  static const double _titleHeight = 58;
  static const double _titleSpacing = 6;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final coverScale = BookListController.sharedCoverScale.value;
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
              final item = items[idx];
              return BookItemCard(
                key: ValueKey('book_history_${item.id}'),
                item: item,
                mobileLayout: true,
                showSelectionCheckbox: false,
              );
            }, childCount: items.length),
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
