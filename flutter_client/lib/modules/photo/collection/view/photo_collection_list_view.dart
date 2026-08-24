import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/custom_album.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_expandable_search_bar.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../base/components/custom_popup_select_button.dart';
import '../controller/photo_collection_controller.dart';
import '../models/photo_collection_model.dart';
import '../../timeline/view/pc_photo_timeline.dart';
import 'dialogs/photo_collection_create_edit_dialog.dart';

part 'parts/photo_collection_card.dart';
part 'parts/photo_collection_dialogs.dart';
part 'parts/photo_collection_preview.dart';
part 'parts/photo_collection_timeline_overlay.dart';
part 'parts/photo_collection_top_bar.dart';

class PhotoCollectionListView extends StatefulWidget {
  final bool autoOpenCreate;
  const PhotoCollectionListView({super.key, this.autoOpenCreate = false});

  @override
  State<PhotoCollectionListView> createState() =>
      _PhotoCollectionListViewState();
}

class _PhotoCollectionListViewState extends State<PhotoCollectionListView> {
  bool _didAutoOpenCreate = false;

  @override
  Widget build(BuildContext context) {
    const tag = 'photo_collection';
    return GetBuilder<PhotoCollectionController>(
      init: PhotoCollectionController(),
      tag: tag,
      dispose: (_) => Get.delete<PhotoCollectionController>(tag: tag),
      builder: (ctrl) {
        if (widget.autoOpenCreate && !_didAutoOpenCreate) {
          _didAutoOpenCreate = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showCreateDialog(context, ctrl);
          });
        }
        final content = Obx(() {
          if (ctrl.isLoading.value && ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.items.isEmpty) {
            return CustomNoData(text: 'no_data'.tr);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = (width / 280).floor().clamp(1, 4);
              return CustomScrollView(
                controller: ctrl.scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.5,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final collection = ctrl.items[index];
                        return _CollectionCard(
                          collection: collection,
                          onOpen: () {
                            ctrl.openCollection(collection);
                          },
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
            },
          );
        });

        final list = Column(
          children: [
            _TopBar(controller: ctrl),
            Expanded(child: content),
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
                return _CollectionTimelineOverlay(
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
