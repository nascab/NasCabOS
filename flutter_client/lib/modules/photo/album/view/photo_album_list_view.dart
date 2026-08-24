import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/custom_album.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../../base/components/custom_context_menu_item.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_expandable_search_bar.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../../utils/dialog_util.dart';
import '../../../base/components/custom_popup_select_button.dart';
import '../controller/photo_album_controller.dart';
import '../models/photo_album_model.dart';
import '../../timeline/view/pc_photo_timeline.dart';
import 'dialogs/photo_album_create_edit_dialog.dart';
part 'parts/photo_album_list_dialogs_create_edit.dart';
part 'parts/photo_album_list_dialogs_delete.dart';
part 'parts/photo_album_list_top_bar.dart';
part 'parts/photo_album_list_card.dart';
part 'parts/photo_album_list_timeline_overlay.dart';

class PhotoAlbumListView extends StatefulWidget {
  final String type;
  final bool selectionMode;
  final bool autoOpenCreate;
  const PhotoAlbumListView({
    super.key,
    this.type = 'all',
    this.selectionMode = false,
    this.autoOpenCreate = false,
  });

  @override
  State<PhotoAlbumListView> createState() => _PhotoAlbumListViewState();
}

class _PhotoAlbumListViewState extends State<PhotoAlbumListView> {
  bool _didAutoOpenCreate = false;

  @override
  Widget build(BuildContext context) {
    final tag = 'photo_album_${widget.type}';
    return GetBuilder<PhotoAlbumController>(
      init: PhotoAlbumController(type: widget.type),
      tag: tag,
      dispose: (_) => Get.delete<PhotoAlbumController>(tag: tag),
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
            if (widget.selectionMode) {
              return Center(
                child: CustomButton(
                  text: 'create'.tr,
                  icon: const Icon(Icons.add),
                  onPressed: () => _showCreateDialog(context, ctrl),
                ),
              );
            }
            return CustomNoData(text: 'no_data'.tr);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = (width / 240).floor().clamp(2, 6);
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
                        childAspectRatio: 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final album = ctrl.items[index];
                        return _AlbumCard(
                          album: album,
                          selectionMode: widget.selectionMode,
                          onOpen: widget.selectionMode
                              ? () => Navigator.of(context).pop(album)
                              : () {
                                  ctrl.openAlbum(album);
                                },
                          onDownload: () => ctrl.downloadAlbums([album.id]),
                          onEdit: () => _showEditDialog(context, ctrl, album),
                          onDelete: () => _confirmDelete(context, ctrl, album),

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
            _TopBar(controller: ctrl, selectionMode: widget.selectionMode),
            Expanded(child: content),
          ],
        );

        if (widget.selectionMode) {
          return list;
        }
        final customColors = Theme.of(context).extension<CustomColors>();

        return Container(
          decoration: BoxDecoration(color: customColors?.mainContentBgColor),
          child: Stack(
            children: [
              list,
              Obx(() {
                final album = ctrl.activeAlbum.value;
                if (album == null) return const SizedBox.shrink();
                return _AlbumTimelineOverlay(
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
