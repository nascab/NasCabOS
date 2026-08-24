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
import '../../../../utils/context_menu_util.dart';
import '../../../../utils/dialog_util.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/video_utils/video_utils.dart';
import '../../list/view/video_list_page.dart';
import '../controller/video_smart_album_controller.dart';
import '../models/video_smart_album_model.dart';

part 'parts/video_smart_album_list_card.dart';
part 'parts/video_smart_album_list_dialogs.dart';
part 'parts/video_smart_album_list_overlay.dart';
part 'parts/video_smart_album_list_top_bar.dart';

class VideoSmartAlbumListView extends StatelessWidget {
  const VideoSmartAlbumListView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'video_smart_album';
    return GetBuilder<VideoSmartAlbumController>(
      init: VideoSmartAlbumController(),
      tag: tag,
      dispose: (_) => Get.delete<VideoSmartAlbumController>(tag: tag),
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
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final album = ctrl.items[index];
                              return _SmartAlbumCard(
                                controller: ctrl,
                                album: album,
                                onOpen: () => ctrl.openAlbum(album),
                                onEdit: () =>
                                    _showEditDialog(context, ctrl, album),
                                onDelete: () =>
                                    _confirmDelete(context, ctrl, album),
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
                final album = ctrl.activeAlbum.value;
                if (album == null) return const SizedBox.shrink();
                return _SmartAlbumOverlay(
                  album: album,
                  onClose: ctrl.closeAlbum,
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
