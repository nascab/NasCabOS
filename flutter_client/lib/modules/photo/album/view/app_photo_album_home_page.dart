import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../../utils/dialog_util.dart';
import '../../collection/view/app_photo_collection_list_page.dart';
import '../../smart_album/view/app_photo_smart_album_list_page.dart';
import '../controller/photo_album_overview_controller.dart';
import '../models/photo_album_model.dart';
import '../../collection/models/photo_collection_model.dart';
import '../../collection/service/photo_collection_api_service.dart';
import '../../collection/view/dialogs/photo_collection_create_edit_dialog.dart';
import '../../smart_album/models/photo_smart_album_model.dart';
import '../../smart_album/controller/photo_smart_album_controller.dart';
import '../../smart_album/service/photo_smart_album_api_service.dart';
import '../../timeline/view/app_photo_album_timeline_page.dart';
import 'app_photo_album_list_page.dart';
import '../service/photo_album_api_service.dart';
import 'dialogs/photo_album_create_edit_dialog.dart';

class AppPhotoAlbumHomePage extends StatefulWidget {
  const AppPhotoAlbumHomePage({super.key});

  @override
  State<AppPhotoAlbumHomePage> createState() => _AppPhotoAlbumHomePageState();
}

class _AppPhotoAlbumHomePageState extends State<AppPhotoAlbumHomePage> {
  late final String _tag;
  late final PhotoAlbumOverviewController _ctrl;
  final PhotoAlbumApiService _albumApi = PhotoAlbumApiService();
  final PhotoCollectionApiService _collectionApi = PhotoCollectionApiService();
  final PhotoSmartAlbumApiService _smartAlbumApi = PhotoSmartAlbumApiService();

  @override
  void initState() {
    super.initState();
    _tag = 'app_photo_album_overview_${UniqueKey()}';
    _ctrl = Get.put(PhotoAlbumOverviewController(limit: 6), tag: _tag);
  }

  @override
  void dispose() {
    Get.delete<PhotoAlbumOverviewController>(tag: _tag, force: true);
    super.dispose();
  }

  Future<void> _openAlbumList({bool autoOpenCreate = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppPhotoAlbumListPage(
          selectionMode: false,
          type: 'all',
          autoOpenCreate: autoOpenCreate,
        ),
      ),
    );
    _ctrl.refreshOverview();
  }

  Future<void> _openSmartAlbumList({bool autoOpenCreate = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AppPhotoSmartAlbumListPage(autoOpenCreate: autoOpenCreate),
      ),
    );
    _ctrl.refreshOverview();
  }

  Future<void> _openCollectionList({bool autoOpenCreate = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AppPhotoCollectionListPage(autoOpenCreate: autoOpenCreate),
      ),
    );
    _ctrl.refreshOverview();
  }

  Future<void> _showAlbumActions(PhotoAlbumItem album) async {
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
                        type: AppPhotoAlbumTimelineType.album,
                        id: album.id,
                        name: album.name,
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
                  await showPhotoAlbumEditDialogWithApi(
                    context,
                    album,
                    _albumApi,
                  );
                  _ctrl.refreshOverview();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('delete'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await DialogUtil.showConfirmDialog(
                    title: 'tip'.tr,
                    content: 'photo_album_delete_confirm'.trParams({
                      'name': album.name,
                    }),
                  );
                  if (ok != true) return;
                  final res = await _albumApi.deleteAlbum(album.id);
                  if (!res.success) {
                    if (res.message != null) {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: res.message!,
                      );
                    }
                    return;
                  }
                  _ctrl.refreshOverview();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSmartAlbumActions(PhotoSmartAlbumItem album) async {
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
                        type: AppPhotoAlbumTimelineType.smartAlbum,
                        id: album.id,
                        name: album.name,
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
                  await _openSmartAlbumList();
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
                  final res = await _smartAlbumApi.deleteSmartAlbum(album.id);
                  if (!res.success) {
                    if (res.message != null) {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: res.message!,
                      );
                    }
                    return;
                  }
                  _ctrl.refreshOverview();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCollectionActions(PhotoCollectionItem collection) async {
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
                  await showPhotoCollectionEditDialogWithSubmit(
                    context,
                    collection,
                    onSubmit:
                        ({
                          required int id,
                          required String name,
                          required List<String> pathList,
                        }) async {
                          final res = await _collectionApi.updateCollection(
                            id: id,
                            name: name,
                            pathList: pathList,
                          );
                          if (!res.success && res.message != null) {
                            DialogUtil.showInfoDialog(
                              title: "tip".tr,
                              content: res.message!,
                            );
                          }
                          return res.success;
                        },
                  );
                  _ctrl.refreshOverview();
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
                  final res = await _collectionApi.deleteCollection(
                    collection.id,
                  );
                  if (!res.success) {
                    if (res.message != null) {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: res.message!,
                      );
                    }
                    return;
                  }
                  _ctrl.refreshOverview();
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
    final customColors = Theme.of(context).extension<CustomColors>();
    return Scaffold(
      backgroundColor: customColors?.mainContentBgColor,
      body: GetBuilder<PhotoAlbumOverviewController>(
        tag: _tag,
        builder: (_) {
          return RefreshIndicator(
            onRefresh: _ctrl.refreshOverview,
            child: Obx(() {
              final isEmpty =
                  _ctrl.albums.isEmpty &&
                  _ctrl.smartAlbums.isEmpty &&
                  _ctrl.collections.isEmpty;
              if (_ctrl.isLoading.value && isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                children: [
                  _Section(
                    title: 'photo_menu_album_normal'.tr,
                    total: _ctrl.albumTotal.value,
                    onMore: _openAlbumList,
                    child: _HorizontalAlbumList(
                      items: _ctrl.albums,
                      builder: (item) => _AlbumCard(
                        album: item,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppPhotoAlbumTimelinePage(
                              type: AppPhotoAlbumTimelineType.album,
                              id: item.id,
                              name: item.name,
                            ),
                          ),
                        ),
                        onMore: () => _showAlbumActions(item),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'photo_menu_album_smart'.tr,
                    total: _ctrl.smartAlbumTotal.value,
                    onMore: _openSmartAlbumList,
                    child: _HorizontalAlbumList(
                      items: _ctrl.smartAlbums,
                      builder: (item) => _SmartAlbumCard(
                        album: item,
                        onInfo: () {
                          final content =
                              PhotoSmartAlbumController.buildAlbumTooltipText(
                                item,
                              );
                          DialogUtil.showInfoDialog(
                            title: item.name,
                            content: (content == null || content.trim().isEmpty)
                                ? 'no_data'.tr
                                : content,
                          );
                        },
                        onMore: () => _showSmartAlbumActions(item),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppPhotoAlbumTimelinePage(
                              type: AppPhotoAlbumTimelineType.smartAlbum,
                              id: item.id,
                              name: item.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'photo_menu_album_collection'.tr,
                    total: _ctrl.collectionTotal.value,
                    onMore: _openCollectionList,
                    child: _HorizontalAlbumList(
                      items: _ctrl.collections,
                      builder: (item) => _CollectionCard(
                        collection: item,
                        onInfo: () {
                          final lines = item.pathList
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                          DialogUtil.showInfoDialog(
                            title: item.name,
                            content: lines.isEmpty
                                ? 'no_data'.tr
                                : lines.join('\n'),
                          );
                        },
                        onMore: () => _showCollectionActions(item),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppPhotoAlbumTimelinePage(
                              type: AppPhotoAlbumTimelineType.collection,
                              id: item.id,
                              name: item.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final int total;
  final VoidCallback onMore;
  final Widget child;

  const _Section({
    required this.title,
    required this.total,
    required this.onMore,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalText = total > 0 ? ' ($total)' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onMore,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$title$totalText',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 148, child: child),
      ],
    );
  }
}

class _HorizontalAlbumList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(T item) builder;

  const _HorizontalAlbumList({required this.items, required this.builder});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'no_data'.tr,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final count = items.length.clamp(0, 6);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      itemCount: count,
      separatorBuilder: (_, index) => const SizedBox(width: 10),
      itemBuilder: (_, index) =>
          SizedBox(width: 160, child: builder(items[index])),
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

class _AlbumCard extends StatelessWidget {
  final PhotoAlbumItem album;
  final VoidCallback onTap;
  final VoidCallback onMore;
  const _AlbumCard({
    required this.album,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = album.previews.isNotEmpty ? album.previews.first : null;
    final url = cover == null
        ? ''
        : ApiController.instance.getTinyUrl(cover.fullpath);

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
                  Icon(
                    album.isPublic ? Icons.public : Icons.lock_outline,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      album.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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

class _SmartAlbumCard extends StatelessWidget {
  final PhotoSmartAlbumItem album;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onInfo;
  const _SmartAlbumCard({
    required this.album,
    required this.onTap,
    required this.onMore,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = album.previews.isNotEmpty ? album.previews.first : null;
    final url = cover == null
        ? ''
        : ApiController.instance.getTinyUrl(cover.fullpath);

    final isDate = album.type == 'smart_date';
    final icon = isDate ? Icons.calendar_month_outlined : Icons.rule_outlined;

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
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      album.name,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
