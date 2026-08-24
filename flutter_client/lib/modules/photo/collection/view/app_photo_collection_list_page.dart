import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/app_custom_search_dialog.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../../utils/dialog_util.dart';
import '../../timeline/view/app_photo_album_timeline_page.dart';
import '../controller/photo_collection_controller.dart';
import '../models/photo_collection_model.dart';
import 'dialogs/photo_collection_create_edit_dialog.dart';

class AppPhotoCollectionListPage extends StatefulWidget {
  final bool autoOpenCreate;
  const AppPhotoCollectionListPage({super.key, this.autoOpenCreate = false});

  @override
  State<AppPhotoCollectionListPage> createState() =>
      _AppPhotoCollectionListPageState();
}

class _AppPhotoCollectionListPageState
    extends State<AppPhotoCollectionListPage> {
  late final String _tag;
  bool _didAutoOpenCreate = false;

  @override
  void initState() {
    super.initState();
    _tag = 'app_photo_collection_list_${UniqueKey()}';
  }

  Future<void> _showMobileSortSheet(PhotoCollectionController ctrl) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget item({
          required String title,
          required bool selected,
          required VoidCallback onTap,
        }) {
          return ListTile(
            title: Text(title),
            trailing: selected ? const Icon(Icons.check, size: 18) : null,
            onTap: onTap,
          );
        }

        return SafeArea(
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
              item(
                title: 'photo_album_sort_name_asc'.tr,
                selected: ctrl.sortField.value == 'name' && ctrl.sortOrder.value == 'asc',
                onTap: () {
                  Navigator.of(ctx).pop();
                  ctrl.setSort(field: 'name', order: 'asc');
                },
              ),
              item(
                title: 'photo_album_sort_name_desc'.tr,
                selected: ctrl.sortField.value == 'name' && ctrl.sortOrder.value == 'desc',
                onTap: () {
                  Navigator.of(ctx).pop();
                  ctrl.setSort(field: 'name', order: 'desc');
                },
              ),
              item(
                title: 'photo_album_sort_create_time_asc'.tr,
                selected: ctrl.sortField.value == 'create_time' && ctrl.sortOrder.value == 'asc',
                onTap: () {
                  Navigator.of(ctx).pop();
                  ctrl.setSort(field: 'create_time', order: 'asc');
                },
              ),
              item(
                title: 'photo_album_sort_create_time_desc'.tr,
                selected: ctrl.sortField.value == 'create_time' && ctrl.sortOrder.value == 'desc',
                onTap: () {
                  Navigator.of(ctx).pop();
                  ctrl.setSort(field: 'create_time', order: 'desc');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCollectionActions(
    PhotoCollectionController ctrl,
    PhotoCollectionItem collection,
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppPhotoAlbumTimelinePage(
                        type: AppPhotoAlbumTimelineType.collection,
                        id: collection.id,
                        name: collection.name,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await showPhotoCollectionEditDialog(
                    context,
                    ctrl,
                    collection,
                  );
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
    return GetBuilder<PhotoCollectionController>(
      init: PhotoCollectionController(),
      tag: _tag,
      dispose: (_) => Get.delete<PhotoCollectionController>(tag: _tag),
      builder: (ctrl) {
        if (widget.autoOpenCreate && !_didAutoOpenCreate) {
          _didAutoOpenCreate = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showPhotoCollectionCreateDialog(context, ctrl);
          });
        }

        final content = Obx(() {
          if (ctrl.isLoading.value && ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (ctrl.items.isEmpty) {
            return CustomNoData(
              text: 'no_data'.tr,
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width <= 750
                  ? 1
                  : (width / 380).floor().clamp(1, 4);
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
                        childAspectRatio: crossAxisCount == 1 ? 2.7 : 1.8,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final collection = ctrl.items[index];
                        return _CollectionCard(
                          collection: collection,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AppPhotoAlbumTimelinePage(
                                type: AppPhotoAlbumTimelineType.collection,
                                id: collection.id,
                                name: collection.name,
                              ),
                            ),
                          ),
                          onInfo: () {
                            final lines = collection.pathList
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                            DialogUtil.showInfoDialog(
                              title: collection.name,
                              content: lines.isEmpty
                                  ? 'no_data'.tr
                                  : lines.join('\n'),
                            );
                          },
                          onMore: () =>
                              _showCollectionActions(ctrl, collection),
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
            title: Text('photo_menu_album_collection'.tr),
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
                onPressed: () => showPhotoCollectionCreateDialog(context, ctrl),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: ctrl.refreshCollections,
            child: content,
          ),
        );
      },
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String url;
  const _PreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest;
    if (url.isEmpty) {
      return Container(
        color: bg,
        alignment: Alignment.center,
        child: Image.asset(
          'assets/icons/no_data.png',
          width: 54,
          height: 54,
          fit: BoxFit.contain,
        ),
      );
    }
    return CustomExtendedImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      borderRadius: 0,
      showLoading: false,
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final PhotoCollectionItem collection;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onInfo;
  const _CollectionCard({
    required this.collection,
    required this.onTap,
    required this.onMore,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = collection.previews.isNotEmpty
        ? collection.previews.first
        : null;
    final url = cover == null
        ? ''
        : ApiController.instance.getTinyUrl(cover.fullpath);

    final pathCount = collection.pathList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: _PreviewImage(url: url)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      collection.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$pathCount',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: onInfo,
                  borderRadius: BorderRadius.circular(18),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(18),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.more_horiz,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
