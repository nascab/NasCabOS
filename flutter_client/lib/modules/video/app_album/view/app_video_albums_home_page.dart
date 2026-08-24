import 'package:NasCabOS/modules/video/app_album/view/app_video_album_list_page.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_collection_list_page.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_smart_album_list_page.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_card.dart';
import 'package:NasCabOS/modules/video/app_album/view/app_video_album_videos_page.dart';
import 'package:NasCabOS/modules/video/album/models/video_album_model.dart';
import 'package:NasCabOS/modules/video/album/service/video_album_api_service.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:NasCabOS/modules/video/collection/models/video_collection_model.dart';
import 'package:NasCabOS/modules/video/collection/service/video_collection_api_service.dart';
import 'package:NasCabOS/modules/video/smart_album/models/video_smart_album_model.dart';
import 'package:NasCabOS/modules/video/smart_album/service/video_smart_album_api_service.dart';
import 'package:NasCabOS/modules/video/smart_album/utils/video_smart_album_tooltip_util.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoAlbumsHomePage extends StatefulWidget {
  const AppVideoAlbumsHomePage({super.key});

  @override
  State<AppVideoAlbumsHomePage> createState() => _AppVideoAlbumsHomePageState();
}

class _AppVideoAlbumsHomePageState extends State<AppVideoAlbumsHomePage> {
  bool _loading = true;
  List<VideoSmartAlbumItem> _smartItems = const <VideoSmartAlbumItem>[];
  List<VideoCollectionItem> _collectionItems = const <VideoCollectionItem>[];
  List<VideoAlbumItem> _albumItems = const <VideoAlbumItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> _smartAlbumPreviewUrls(
    List<VideoSmartAlbumPreviewItem> previews,
  ) {
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

  List<String> _collectionPreviewUrls(
    List<VideoCollectionPreviewItem> previews,
  ) {
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

  List<String> _albumPreviewUrls(List<VideoAlbumPreviewItem> previews) {
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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final res = await VideoAlbumApiService.instance.getAlbumOverview(
        limit: 10,
      );
      final data = res.data;
      if (!res.success || data == null) return;
      if (!mounted) return;
      setState(() {
        _smartItems = data.smartAlbums.take(10).toList();
        _collectionItems = data.collections.take(10).toList();
        _albumItems = data.albums.take(10).toList();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showSmartAlbumActions(VideoSmartAlbumItem album) async {
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
                    () => AppVideoAlbumVideosPage.smartAlbum(
                      smartAlbumId: album.id,
                      name: album.name,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(
                    () => AppVideoSmartAlbumListPage(initialEditId: album.id),
                  )?.then((_) => _load());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'tip'.tr,
                    content: '${'delete'.tr} "${album.name}" ?',
                  );
                  if (ok != true) return;
                  final res = await VideoSmartAlbumApiService.instance
                      .deleteSmartAlbum(album.id);
                  if (res.success) {
                    await _load();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCollectionActions(VideoCollectionItem collection) async {
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
                  Get.to(
                    () => AppVideoCollectionListPage(
                      initialEditId: collection.id,
                    ),
                  )?.then((_) => _load());
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
                  final res = await VideoCollectionApiService()
                      .deleteCollection(collection.id);
                  if (res.success) {
                    await _load();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAlbumActions(VideoAlbumItem album) async {
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
                    () => AppVideoAlbumVideosPage.album(
                      albumId: album.id,
                      name: album.name,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Get.to(
                    () => AppVideoAlbumListPage(initialEditId: album.id),
                  )?.then((_) => _load());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'tip'.tr,
                    content: '${'delete'.tr} "${album.name}" ?',
                  );
                  if (ok != true) return;
                  final res = await VideoAlbumApiService.instance.deleteAlbum(
                    album.id,
                  );
                  if (res.success) {
                    await _load();
                  }
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
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final padBottom = MediaQuery.of(context).padding.bottom;

    Widget sectionTitle({required String title, required VoidCallback onTap}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget horizontalList<T>({
      required List<T> items,
      required Widget Function(BuildContext ctx, T item) itemBuilder,
      double widthScale = 1.6,
    }) {
      final width = MediaQuery.of(context).size.width;
      const padding = 20.0;
      const spacing = 15.0;
      final estimated = (width - padding * 2 - spacing) / 2.2;
      final baseWidth = estimated.clamp(160.0, 260.0);
      final baseCardWidth = (baseWidth * 1.5).clamp(240.0, 420.0);
      final itemWidth = (baseWidth * widthScale).clamp(240.0, 460.0);
      final itemHeight = ((baseCardWidth / 1.6) * 1.1).clamp(200.0, 360.0);

      return SizedBox(
        height: itemHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemBuilder: (ctx, index) =>
              SizedBox(width: itemWidth, child: itemBuilder(ctx, items[index])),
          separatorBuilder: (ctx, index) => const SizedBox(width: spacing),
          itemCount: items.length,
        ),
      );
    }

    Widget noDataHint() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Center(
          child: Text(
            'no_data'.tr,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return Material(
      color: customColors?.mainContentBgColor,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            bottom: padBottom + 70,
          ),
          children: [
            sectionTitle(
              title: 'video_custom_album_title'.tr,
              onTap: () {
                Get.to(() => const AppVideoAlbumListPage())?.then((_) => _load());
              },
            ),
            if (_albumItems.isNotEmpty)
              horizontalList<VideoAlbumItem>(
                items: _albumItems,
                itemBuilder: (ctx, album) {
                  return AppVideoAlbumCard(
                    title: album.name,
                    titleIcon: Icons.video_collection_outlined,
                    previewUrls: _albumPreviewUrls(album.previews),
                    onTap: () => Get.to(
                      () => AppVideoAlbumVideosPage.album(
                        albumId: album.id,
                        name: album.name,
                      ),
                    ),
                    onMore: () => _showAlbumActions(album),
                  );
                },
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              noDataHint(),
            sectionTitle(
              title: 'video_smart_album_title'.tr,
              onTap: () {
                Get.to(
                  () => const AppVideoSmartAlbumListPage(),
                )?.then((_) => _load());
              },
            ),
            if (_smartItems.isNotEmpty)
              horizontalList<VideoSmartAlbumItem>(
                items: _smartItems,
                itemBuilder: (ctx, album) {
                  return AppVideoAlbumCard(
                    title: album.name,
                    titleIcon: Icons.filter_alt_outlined,
                    topLeftIcon: Icons.info_outline,
                    onTopLeftTap: () {
                      final tip = _buildSmartAlbumTooltip(album) ?? '';
                      DialogUtil.showInfoDialog(
                        title: album.name,
                        content: tip.trim().isEmpty ? 'no_data'.tr : tip,
                      );
                    },
                    previewUrls: _smartAlbumPreviewUrls(album.previews),
                    onTap: () => Get.to(
                      () => AppVideoAlbumVideosPage.smartAlbum(
                        smartAlbumId: album.id,
                        name: album.name,
                      ),
                    ),
                    onMore: () => _showSmartAlbumActions(album),
                  );
                },
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              noDataHint(),
            sectionTitle(
              title: 'video_collection_title'.tr,
              onTap: () {
                Get.to(
                  () => const AppVideoCollectionListPage(),
                )?.then((_) => _load());
              },
            ),
            if (_collectionItems.isNotEmpty)
              horizontalList<VideoCollectionItem>(
                items: _collectionItems,
                itemBuilder: (ctx, collection) {
                  return AppVideoAlbumCard(
                    title: collection.name,
                    titleIcon: Icons.collections_bookmark_outlined,
                    topLeftIcon: Icons.info_outline,
                    onTopLeftTap: () {
                      final paths = collection.pathList
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                      final content = paths.isEmpty
                          ? 'no_path'.tr
                          : '${'path'.tr}:\n${paths.join('\n')}';
                      DialogUtil.showInfoDialog(
                        title: collection.name,
                        content: content,
                      );
                    },
                    previewUrls: _collectionPreviewUrls(collection.previews),
                    onTap: () => Get.to(
                      () => AppVideoAlbumVideosPage.collection(
                        collectionId: collection.id,
                        name: collection.name,
                      ),
                    ),
                    onMore: () => _showCollectionActions(collection),
                  );
                },
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              noDataHint(),
          ],
        ),
      ),
    );
  }
}

String? _buildSmartAlbumTooltip(VideoSmartAlbumItem album) {
  return VideoSmartAlbumTooltipUtil.buildTooltip(album.filterContent);
}
