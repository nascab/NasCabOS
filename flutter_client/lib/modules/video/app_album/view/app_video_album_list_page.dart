import 'package:NasCabOS/modules/base/components/app_custom_search_dialog.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_card.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_videos_page.dart';
import 'package:NasCabOS/modules/video/album/controller/video_album_controller.dart';
import 'package:NasCabOS/modules/video/album/models/video_album_model.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoAlbumListPage extends StatefulWidget {
  final int? initialEditId;

  const AppVideoAlbumListPage({super.key, this.initialEditId});

  @override
  State<AppVideoAlbumListPage> createState() => _AppVideoAlbumListPageState();
}

class _AppVideoAlbumListPageState extends State<AppVideoAlbumListPage> {
  late final String _tag;
  bool _didAutoEdit = false;

  @override
  void initState() {
    super.initState();
    _tag = 'app_video_album_list_${UniqueKey()}';
  }

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

  Future<void> _showSortSheet(VideoAlbumController ctrl) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'sort'.tr,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                ListTile(
                  title: Text('name_asc'.tr),
                  trailing:
                      ctrl.sortField.value == 'name' &&
                          ctrl.sortOrder.value == 'asc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'name', order: 'asc');
                  },
                ),
                ListTile(
                  title: Text('name_desc'.tr),
                  trailing:
                      ctrl.sortField.value == 'name' &&
                          ctrl.sortOrder.value == 'desc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'name', order: 'desc');
                  },
                ),
                ListTile(
                  title: Text('create_time_asc'.tr),
                  trailing:
                      ctrl.sortField.value == 'create_time' &&
                          ctrl.sortOrder.value == 'asc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'create_time', order: 'asc');
                  },
                ),
                ListTile(
                  title: Text('create_time_desc'.tr),
                  trailing:
                      ctrl.sortField.value == 'create_time' &&
                          ctrl.sortOrder.value == 'desc'
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ctrl.setSort(field: 'create_time', order: 'desc');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog(VideoAlbumController ctrl) async {
    final nameCtrl = TextEditingController();
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
                          final ok = await ctrl.createAlbum(
                            name: nameCtrl.text,
                            isPublic: false,
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
    VideoAlbumController ctrl,
    VideoAlbumItem album,
  ) async {
    final nameCtrl = TextEditingController(text: album.name);
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
                          final ok = await ctrl.updateAlbum(
                            id: album.id,
                            name: nameCtrl.text,
                            isPublic: album.isPublic,
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
    VideoAlbumController ctrl,
    VideoAlbumItem album,
  ) async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'tip'.tr,
      content: '${'delete'.tr} "${album.name}" ?',
    );
    if (ok != true) return;
    await ctrl.deleteAlbum(album.id);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoAlbumController>(
      init: VideoAlbumController(),
      tag: _tag,
      dispose: (_) => Get.delete<VideoAlbumController>(tag: _tag),
      builder: (ctrl) {
        return Obx(() {
          final loading = ctrl.isLoading.value && ctrl.items.isEmpty;
          final items = ctrl.items.toList();

          if (!_didAutoEdit &&
              (widget.initialEditId ?? 0) > 0 &&
              items.isNotEmpty) {
            _didAutoEdit = true;
            final id = widget.initialEditId!;
            final idx = items.indexWhere((e) => e.id == id);
            if (idx != -1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showEditDialog(ctrl, items[idx]);
              });
            }
          }

          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: Text('video_custom_album_title'.tr),
              actions: [
                Obx(() {
                  final hasKeyword = ctrl.keyword.value.isNotEmpty;
                  return IconButton(
                    tooltip: 'search'.tr,
                    onPressed: () => AppCustomSearchDialog.show(
                      context: context,
                      hintText: 'search'.tr,
                      controller: ctrl.searchController,
                      onChanged: ctrl.onSearchChanged,
                      onClear: ctrl.clearSearch,
                    ),
                    icon: hasKeyword
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.search),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const Icon(Icons.search),
                  );
                }),
                IconButton(
                  tooltip: 'sort'.tr,
                  onPressed: () => _showSortSheet(ctrl),
                  icon: const Icon(Icons.sort_by_alpha),
                ),
                IconButton(
                  tooltip: 'create'.tr,
                  onPressed: () => _showCreateDialog(ctrl),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            body: SafeArea(
              child: RefreshIndicator(
                onRefresh: ctrl.refreshAlbums,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : (items.isEmpty
                          ? CustomNoData(text: 'no_data'.tr)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                              itemCount: items.length + 1,
                              separatorBuilder: (ctx, i) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (ctx, i) {
                                if (i >= items.length) {
                                  if (ctrl.isLoading.value) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (!ctrl.hasMore.value) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'no_more'.tr,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Center(
                                      child: OutlinedButton(
                                        onPressed: ctrl.loadMore,
                                        child: Text('load_more'.tr),
                                      ),
                                    ),
                                  );
                                }

                                final album = items[i];
                                return AspectRatio(
                                  aspectRatio: 1.7,
                                  child: AppVideoAlbumCard(
                                    title: album.name,
                                    titleIcon: Icons.video_collection_outlined,
                                    previewUrls: _previewUrls(album.previews),
                                    onTap: () => Get.to(
                                      () => AppVideoAlbumVideosPage.album(
                                        albumId: album.id,
                                        name: album.name,
                                      ),
                                    ),
                                    onMore: () async {
                                      await showModalBottomSheet<void>(
                                        context: context,
                                        builder: (sheetCtx) {
                                          return SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.open_in_new,
                                                  ),
                                                  title: Text('open'.tr),
                                                  onTap: () {
                                                    Navigator.of(
                                                      sheetCtx,
                                                    ).pop();
                                                    Get.to(
                                                      () =>
                                                          AppVideoAlbumVideosPage.album(
                                                            albumId: album.id,
                                                            name: album.name,
                                                          ),
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  title: Text('edit'.tr),
                                                  onTap: () {
                                                    Navigator.of(
                                                      sheetCtx,
                                                    ).pop();
                                                    _showEditDialog(
                                                      ctrl,
                                                      album,
                                                    );
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.delete_outline,
                                                  ),
                                                  title: Text('delete'.tr),
                                                  onTap: () async {
                                                    Navigator.of(
                                                      sheetCtx,
                                                    ).pop();
                                                    await _confirmDelete(
                                                      ctrl,
                                                      album,
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                );
                              },
                            )),
              ),
            ),
          );
        });
      },
    );
  }
}
