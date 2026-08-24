import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../controller/book_collection_controller.dart';
import 'parts/book_collection_card.dart';
import 'parts/book_collection_dialogs.dart';
import 'parts/book_collection_overlay.dart';
import 'parts/book_collection_top_bar.dart';

class BookCollectionListView extends StatelessWidget {
  const BookCollectionListView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'book_collection';
    return GetBuilder<BookCollectionController>(
      init: BookCollectionController(),
      tag: tag,
      dispose: (_) => Get.delete<BookCollectionController>(tag: tag),
      builder: (ctrl) {
        final list = Column(
          children: [
            BookCollectionTopBar(controller: ctrl),
            Expanded(
              child: Obx(() {
                if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (ctrl.items.isEmpty) {
                  return CustomNoData(text: 'no_data'.tr);
                }
                return CustomScrollView(
                  controller: ctrl.scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 380,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.45,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final collection = ctrl.items[index];
                          return BookCollectionCard(
                            collection: collection,
                            onOpen: () => ctrl.openCollection(collection),
                            onEdit: () => BookCollectionDialogs.showEditDialog(
                              context,
                              controller: ctrl,
                              collection: collection,
                            ),
                            onDelete: () => BookCollectionDialogs.confirmDelete(
                              context,
                              controller: ctrl,
                              collection: collection,
                            ),
                          );
                        }, childCount: ctrl.items.length),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: Center(
                            child: ctrl.isLoading.value
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : (!ctrl.hasMore.value
                                      ? Text(
                                          'no_more'.tr,
                                          style: Get.textTheme.bodySmall,
                                        )
                                      : OutlinedButton(
                                          onPressed: ctrl.loadMore,
                                          child: Text('load_more'.tr),
                                        )),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        );
        final customColors = Theme.of(context).extension<CustomColors>();
        return Container(
          decoration: BoxDecoration(color: customColors?.mainContentBgColor),
          child: Stack(
            children: [
              list,
              Obx(() {
                final collection = ctrl.activeCollection.value;
                if (collection == null) return const SizedBox.shrink();
                return BookCollectionBookOverlay(
                  collection: collection,
                  onClose: ctrl.closeCollection,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
