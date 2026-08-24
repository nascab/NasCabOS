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
import '../controller/video_album_controller.dart';
import '../models/video_album_model.dart';
import '../../list/view/video_list_page.dart';

class VideoAlbumListView extends StatelessWidget {
  const VideoAlbumListView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'video_album';
    return GetBuilder<VideoAlbumController>(
      init: VideoAlbumController(),
      tag: tag,
      dispose: (_) => Get.delete<VideoAlbumController>(tag: tag),
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
                          final album = ctrl.items[index];
                          return _AlbumCard(
                            album: album,
                            onOpen: () => ctrl.openAlbum(album),
                            onEdit: () => _showEditDialog(context, ctrl, album),
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
                return _AlbumVideoOverlay(
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

class _TopBar extends StatelessWidget {
  final VideoAlbumController controller;
  const _TopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: customColors?.mainContentBgColor),
      child: Row(
        children: [
          CustomBorderedIconButton(
            icon: Icons.add,
            tooltip: 'create'.tr,
            onTap: () => _showCreateDialog(context, controller),
          ),
          const SizedBox(width: 4),
          Obx(() {
            final cur =
                '${controller.sortField.value}_${controller.sortOrder.value}';
            return CustomPopupSelectButton<String>(
              icon: Icons.sort_by_alpha,
              tooltip: 'sort'.tr,
              value: cur,
              defaultValue: 'create_time_desc',
              items: [
                CustomPopupSelectItem(
                  value: 'name_asc',
                  label: 'name_asc'.tr,
                  icon: Icons.sort_by_alpha,
                ),
                CustomPopupSelectItem(
                  value: 'name_desc',
                  label: 'name_desc'.tr,
                  icon: Icons.sort_by_alpha,
                ),
                CustomPopupSelectItem(
                  value: 'create_time_asc',
                  label: 'create_time_asc'.tr,
                  icon: Icons.schedule,
                ),
                CustomPopupSelectItem(
                  value: 'create_time_desc',
                  label: 'create_time_desc'.tr,
                  icon: Icons.schedule,
                ),
              ],
              onSelected: (next) {
                final parts = next.split('_');
                if (parts.isEmpty) return;
                final order = parts.last;
                final field = parts.sublist(0, parts.length - 1).join('_');
                controller.setSort(field: field, order: order);
              },
            );
          }),
          const SizedBox(width: 10),
          const Spacer(),
          CustomExpandableSearchBar(
            controller: controller.searchController,
            hintText: 'search'.tr,
            onChanged: controller.onSearchChanged,
            onClear: controller.clearSearch,
            expandedWidth: 120,
          ),
        ],
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  final VideoAlbumItem album;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AlbumCard({
    required this.album,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  List<String> _previewUrls(List<VideoAlbumPreviewItem> previews) {
    return previews.take(4).map((e) {
      final item = VideoHomeItemBean(
        id: 0,
        mediaType: '',
        path: '',
        filename: '',
        firstFilePath: e.firstFilePath,
        nfoName: '',
        nfoYear: 0,
        nfoScore: 0,
        nfoRegions: '',
        nfoGenres: '',
        posterPath: '',
        fanartPath: '',
        logoPath: '',
        progress: 0,
        viewTime: null,
        createTime: null,
        fullPath: e.fullpath,
      );
      return VideoUtils.getPosterUrl(item, size: 500);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final headerLeft = Row(
      children: [
        Flexible(
          child: Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  blurRadius: 6,
                  color: Colors.black54,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final headerRight = PopupMenuButton<String>(
      tooltip: '',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (v) {
        if (v == 'open') onOpen();
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) {
        return [
          PopupMenuItem<String>(value: 'open', child: Text('open'.tr)),
          PopupMenuItem<String>(value: 'edit', child: Text('edit'.tr)),
          PopupMenuItem<String>(value: 'delete', child: Text('delete'.tr)),
        ];
      },
    );

    final card = CustomAlbum(
      preview: _AlbumPreviewGrid(urls: _previewUrls(album.previews)),
      onTap: onOpen,
      headerLeft: headerLeft,
      headerRight: headerRight,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
    );

    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => onOpen(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('edit'.tr),
        icon: const Icon(Icons.edit_outlined, size: 18),
        value: 'edit',
        onSelected: (_) => onEdit(),
      ),
      CustomContextMenuItem.create(
        label: Text('delete'.tr),
        icon: const Icon(Icons.delete_outline, size: 18),
        value: 'delete',
        onSelected: (_) => onDelete(),
      ),
    ];

    return ContextMenuUtil.region(child: card, entries: entries);
  }
}

class _AlbumPreviewGrid extends StatelessWidget {
  final List<String> urls;
  const _AlbumPreviewGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeUrls = urls.where((e) => e.trim().isNotEmpty).toList();
    if (safeUrls.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        child: Icon(
          Icons.video_collection_outlined,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          size: 46,
        ),
      );
    }

    final show = safeUrls.take(4).toList();
    if (show.length == 1) {
      return CustomExtendedImage(imageUrl: show.first, fit: BoxFit.cover);
    }

    final grids = show.length <= 3 ? 2 : 4;
    final itemCount = show.length;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: grids == 2 ? 2 : 2,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (ctx, i) {
        return CustomExtendedImage(imageUrl: show[i], fit: BoxFit.cover);
      },
    );
  }
}

class _AlbumVideoOverlay extends StatelessWidget {
  final VideoAlbumItem album;
  final VoidCallback onClose;

  const _AlbumVideoOverlay({required this.album, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Positioned.fill(
      child: Material(
        color: customColors?.mainContentBgColor,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Get.theme.dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'back'.tr,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        "${'video_custom_album_title'.tr}-${album.name}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: VideoListPage(
                  key: ValueKey('album_video_list_${album.id}'),
                  initialMediaType: '',
                  albumId: album.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showCreateDialog(
  BuildContext context,
  VideoAlbumController controller,
) async {
  final nameCtrl = TextEditingController();
  var isPublic = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canSubmit = nameCtrl.text.trim().isNotEmpty;
          return DialogUtil.createAlertDialog(
            title: Text('create'.tr),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'name'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              ElevatedButton(
                onPressed: !canSubmit
                    ? null
                    : () async {
                        final ok = await controller.createAlbum(
                          name: nameCtrl.text,
                          isPublic: isPublic,
                        );
                        if (!ok) return;
                        if (context.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: Text('ok'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showEditDialog(
  BuildContext context,
  VideoAlbumController controller,
  VideoAlbumItem album,
) async {
  final nameCtrl = TextEditingController(text: album.name);
  var isPublic = album.isPublic;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canSubmit = nameCtrl.text.trim().isNotEmpty;
          return DialogUtil.createAlertDialog(
            title: Text('edit'.tr),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'name'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isPublic,
                    onChanged: (v) => setState(() => isPublic = v),
                    title: Text('public'.tr),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              ElevatedButton(
                onPressed: !canSubmit
                    ? null
                    : () async {
                        final ok = await controller.updateAlbum(
                          id: album.id,
                          name: nameCtrl.text,
                          isPublic: isPublic,
                        );
                        if (!ok) return;
                        if (context.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: Text('ok'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _confirmDelete(
  BuildContext context,
  VideoAlbumController controller,
  VideoAlbumItem album,
) async {
  final confirmed = await DialogUtil.showConfirmDialog(
    title: 'tip'.tr,
    content: '${'delete'.tr} ${album.name} ?',
  );
  if (confirmed != true) return;
  await controller.deleteAlbum(album.id);
}
