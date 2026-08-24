import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_album.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_expandable_search_bar.dart';
import '../../../base/components/custom_popup_select_button.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/video_utils/video_utils.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../../utils/dialog_util.dart';
import '../controller/video_collection_controller.dart';
import '../models/video_collection_model.dart';
import '../../list/view/video_list_page.dart';
import '../../../files/views/folder_picker_dialog.dart';

part 'parts/video_collection_card.dart';
part 'parts/video_collection_dialogs.dart';
part 'parts/video_collection_preview.dart';
part 'parts/video_collection_video_overlay.dart';
part 'parts/video_collection_top_bar.dart';

class VideoCollectionListView extends StatelessWidget {
  const VideoCollectionListView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'video_collection';
    return GetBuilder<VideoCollectionController>(
      init: VideoCollectionController(),
      tag: tag,
      dispose: (_) => Get.delete<VideoCollectionController>(tag: tag),
      builder: (ctrl) {
        final list = Column(
          children: [
            _TopBar(controller: ctrl),
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
                              maxCrossAxisExtent: 360,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.55,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final collection = ctrl.items[index];
                          return _CollectionCard(
                            collection: collection,
                            onOpen: () => ctrl.openCollection(collection),
                            onEdit: () =>
                                _showEditDialog(context, ctrl, collection),
                            onDelete: () =>
                                _confirmDelete(context, ctrl, collection),
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
                return _CollectionVideoOverlay(
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
