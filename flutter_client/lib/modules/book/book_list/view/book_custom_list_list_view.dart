import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_button.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../../utils/device_utils.dart';
import '../controller/book_custom_list_controller.dart';
import 'parts/book_custom_list_card.dart';
import 'parts/book_custom_list_dialogs.dart';
import 'parts/book_custom_list_overlay.dart';
import 'parts/book_custom_list_top_bar.dart';

export 'parts/book_custom_list_overlay.dart';

class BookCustomListListView extends StatelessWidget {
  final bool selectionMode;
  const BookCustomListListView({super.key, this.selectionMode = false});

  @override
  Widget build(BuildContext context) {
    final isPhone = DeviceUtils.isPhone(context);
    final tag = 'book_custom_list_${DateTime.now().microsecondsSinceEpoch}';
    return GetBuilder<BookCustomListController>(
      init: BookCustomListController(),
      tag: tag,
      dispose: (_) => Get.delete<BookCustomListController>(tag: tag),
      builder: (ctrl) {
        final list = Column(
          children: [
            selectionMode
                ? (isPhone
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'back'.tr,
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.close),
                                ),
                                Expanded(
                                  child: Text(
                                    'book_list_select'.tr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Get.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : BookCustomListTopBar(
                          controller: ctrl,
                          selectionMode: selectionMode,
                        ))
                : BookCustomListTopBar(
                    controller: ctrl,
                    selectionMode: selectionMode,
                  ),
            Expanded(
              child: Obx(() {
                if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (ctrl.items.isEmpty) {
                  if (selectionMode) {
                    return Center(
                      child: CustomButton(
                        text: 'create'.tr,
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final item =
                              await BookCustomListDialogs.showCreateForSelection(
                                context,
                                controller: ctrl,
                              );
                          if (item != null && context.mounted) {
                            Navigator.of(context).pop(item);
                          }
                        },
                      ),
                    );
                  }
                  return CustomNoData(text: 'no_data'.tr);
                }

                return CustomScrollView(
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
                        delegate: SliverChildBuilderDelegate((
                          context,
                          index,
                        ) {
                          final item = ctrl.items[index];
                          return BookCustomListCard(
                            item: item,
                            selectionMode: selectionMode,
                            onOpen: selectionMode
                                ? () => Navigator.of(context).pop(item)
                                : () => ctrl.openList(item),
                            onRename: () =>
                                BookCustomListDialogs.showRenameDialog(
                                  context,
                                  controller: ctrl,
                                  item: item,
                                ),
                            onDelete: () =>
                                BookCustomListDialogs.confirmDelete(
                                  context,
                                  controller: ctrl,
                                  item: item,
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
                            child: ctrl.isLoading.value &&
                                    ctrl.items.isNotEmpty
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

        if (selectionMode) return list;
        final customColors = Theme.of(context).extension<CustomColors>();
        final overlayCtrl = Get.isRegistered<BookCustomListOverlayController>()
            ? Get.find<BookCustomListOverlayController>()
            : Get.put(BookCustomListOverlayController());
        return Container(
          decoration: BoxDecoration(color: customColors?.mainContentBgColor),
          child: Stack(
            children: [
              list,
              Obx(() {
                final active = overlayCtrl.active.value;
                if (active == null) return const SizedBox.shrink();
                return BookCustomListOverlay(
                  listId: active.listId,
                  name: active.name,
                  onClose: overlayCtrl.close,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
