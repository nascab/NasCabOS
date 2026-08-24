import 'package:NasCabOS/modules/base/components/app_custom_search_dialog.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_card.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_videos_page.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:NasCabOS/modules/video/collection/controller/video_collection_controller.dart';
import 'package:NasCabOS/modules/video/collection/models/video_collection_model.dart';
import 'package:NasCabOS/modules/files/views/folder_picker_dialog.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoCollectionListPage extends StatefulWidget {
  final int? initialEditId;

  const AppVideoCollectionListPage({super.key, this.initialEditId});

  @override
  State<AppVideoCollectionListPage> createState() =>
      _AppVideoCollectionListPageState();
}

class _AppVideoCollectionListPageState
    extends State<AppVideoCollectionListPage> {
  late final String _tag;
  bool _didAutoEdit = false;

  @override
  void initState() {
    super.initState();
    _tag = 'app_video_collection_list_${UniqueKey()}';
  }

  List<String> _previewUrls(List<VideoCollectionPreviewItem> previews) {
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

  Future<void> _showMobileSortSheet(VideoCollectionController ctrl) async {
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

  Widget _buildCreateEditDialogContent({
    required BuildContext context,
    required String nameValue,
    required ValueChanged<String> onNameChanged,
    required VoidCallback onChanged,
    required List<String> pathList,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: nameValue,
            autofocus: true,
            onChanged: (v) {
              onNameChanged(v);
            },
            decoration: InputDecoration(
              labelText: 'photo_collection_name'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final selected = await showFolderPickerBottomSheet(
                      context,
                      multiSelect: true,
                      allowFileSelect: false,
                      sourceType: 'video',
                    );
                    if (selected == null || selected.isEmpty) return;
                    for (final p in selected) {
                      if (!pathList.contains(p)) {
                        pathList.add(p);
                      }
                    }
                    onChanged();
                  },
                  icon: const Icon(Icons.folder_open),
                  label: Text('choose_path'.tr),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pathList.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int index = 0; index < pathList.length; index++) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pathList[index],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'delete'.tr,
                              onPressed: () {
                                pathList.removeAt(index);
                                onChanged();
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                      if (index != pathList.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(VideoCollectionController ctrl) async {
    var name = '';
    final pathList = <String>[];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = name.trim().isNotEmpty && pathList.isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Row(
                children: [
                  Text('photo_create_collection'.tr),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'tip'.tr,
                    onPressed: () => DialogUtil.showInfoDialog(
                      title: 'photo_create_collection'.tr,
                      content: 'photo_create_collection_alert'.tr,
                    ),
                    icon: const Icon(Icons.info_outlined),
                  ),
                ],
              ),
              content: _buildCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                onChanged: () => setState(() {}),
                pathList: pathList,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final nav = Navigator.of(dialogContext);
                          final suc = await ctrl.createCollection(
                            name: name.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            nav.pop();
                          }
                        }
                      : null,
                  child: Text('create'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDialog(
    VideoCollectionController ctrl,
    VideoCollectionItem collection,
  ) async {
    var name = collection.name;
    final pathList = collection.pathList.toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = name.trim().isNotEmpty && pathList.isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Text('edit'.tr),
              content: _buildCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                onChanged: () => setState(() {}),
                pathList: pathList,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final nav = Navigator.of(dialogContext);
                          final suc = await ctrl.updateCollection(
                            id: collection.id,
                            name: name.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            nav.pop();
                          }
                        }
                      : null,
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showActions(
    VideoCollectionController ctrl,
    VideoCollectionItem collection,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text('open'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(
                    () => AppVideoAlbumVideosPage.collection(
                      collectionId: collection.id,
                      name: collection.name,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showEditDialog(ctrl, collection);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'tip'.tr,
                    content: '${'delete'.tr} "${collection.name}" ?',
                  );
                  if (ok != true) return;
                  await ctrl.deleteCollection(collection.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoCollectionController>(
      init: VideoCollectionController(),
      tag: _tag,
      dispose: (_) => Get.delete<VideoCollectionController>(tag: _tag),
      builder: (ctrl) {
        final content = Obx(() {
          if (!_didAutoEdit && widget.initialEditId != null) {
            VideoCollectionItem? target;
            for (final e in ctrl.items) {
              if (e.id == widget.initialEditId) {
                target = e;
                break;
              }
            }
            if (target != null) {
              _didAutoEdit = true;
              final captured = target;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _showEditDialog(ctrl, captured);
              });
            }
          }

          if (ctrl.isLoading.value && ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.items.isEmpty) {
            return CustomNoData(text: 'no_data'.tr);
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width <= 750
                  ? 1
                  : (width / 240).floor().clamp(2, 6);
              return CustomScrollView(
                controller: ctrl.scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: crossAxisCount == 1 ? 2.3 : 1.25,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = ctrl.items[index];
                        return AppVideoAlbumCard(
                          title: item.name,
                          titleIcon: Icons.collections_bookmark_outlined,
                          topLeftIcon: Icons.info_outline,
                          onTopLeftTap: () {
                            final paths = item.pathList
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                            final content = paths.isEmpty
                                ? 'no_path'.tr
                                : '${'path'.tr}:\n${paths.join('\n')}';
                            DialogUtil.showInfoDialog(
                              title: item.name,
                              content: content,
                            );
                          },
                          previewUrls: _previewUrls(item.previews),
                          onTap: () => Get.to(
                            () => AppVideoAlbumVideosPage.collection(
                              collectionId: item.id,
                              name: item.name,
                            ),
                          ),
                          onMore: () => _showActions(ctrl, item),
                        );
                      }, childCount: ctrl.items.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                ],
              );
            },
          );
        });

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text('video_collection_title'.tr),
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
                onPressed: () => _showMobileSortSheet(ctrl),
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
              onRefresh: ctrl.refreshCollections,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
