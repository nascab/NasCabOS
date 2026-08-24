import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:wechat_assets_picker/wechat_assets_picker.dart'
    show PathWrapper, SortPathDelegate;

/// 相册备份：带封面预览的相册选择页（与上传中心同一套排序，保证「全部/最近」等在列表前部）。
Future<pm.AssetPathEntity?> showPhotoBackupAlbumPicker(
  BuildContext context,
) {
  return Navigator.of(context).push<pm.AssetPathEntity>(
    MaterialPageRoute<pm.AssetPathEntity>(
      fullscreenDialog: true,
      builder: (_) => const _PhotoBackupAlbumPickerPage(),
    ),
  );
}

Future<List<pm.AssetPathEntity>> _loadAlbumPaths() async {
  if (Platform.isAndroid) {
    return pm.PhotoManager.getAssetPathList(
      type: pm.RequestType.common,
      hasAll: true,
      onlyAll: false,
      filterOption: pm.AdvancedCustomFilter(
        orderBy: [
          pm.OrderByItem.desc(pm.CustomColumns.android.modifiedDate),
        ],
      ),
    );
  }
  return pm.PhotoManager.getAssetPathList(
    type: pm.RequestType.common,
    hasAll: true,
    onlyAll: false,
  );
}

class _AlbumPreview {
  const _AlbumPreview({required this.count, this.thumbBytes});

  final int count;
  final Uint8List? thumbBytes;
}

Future<_AlbumPreview> _loadAlbumPreview(pm.AssetPathEntity path) async {
  final count = await path.assetCountAsync;
  Uint8List? thumb;
  if (count > 0) {
    final assets = await path.getAssetListRange(start: 0, end: 1);
    if (assets.isNotEmpty) {
      final a = assets.single;
      if (a.type == pm.AssetType.image || a.type == pm.AssetType.video) {
        thumb = await a.thumbnailDataWithSize(
          const pm.ThumbnailSize.square(240),
        );
      }
    }
  }
  return _AlbumPreview(count: count, thumbBytes: thumb);
}

class _PhotoBackupAlbumPickerPage extends StatefulWidget {
  const _PhotoBackupAlbumPickerPage();

  @override
  State<_PhotoBackupAlbumPickerPage> createState() =>
      _PhotoBackupAlbumPickerPageState();
}

class _PhotoBackupAlbumPickerPageState extends State<_PhotoBackupAlbumPickerPage> {
  late final Future<List<PathWrapper<pm.AssetPathEntity>>> _pathsFuture;

  @override
  void initState() {
    super.initState();
    _pathsFuture = _preparePaths();
  }

  Future<List<PathWrapper<pm.AssetPathEntity>>> _preparePaths() async {
    final raw = await _loadAlbumPaths();
    final wrappers =
        raw.map((p) => PathWrapper<pm.AssetPathEntity>(path: p)).toList();
    SortPathDelegate.common.sort(wrappers);
    return wrappers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('photo_album_select'.tr),
      ),
      body: FutureBuilder<List<PathWrapper<pm.AssetPathEntity>>>(
        future: _pathsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final paths = snapshot.data ?? [];
          if (paths.isEmpty) {
            return Center(child: Text('photo_album_empty'.tr));
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: paths.length,
            itemBuilder: (context, index) {
              final path = paths[index].path;
              return _AlbumGridTile(
                path: path,
                theme: theme,
                onTap: () => Navigator.of(context).pop(path),
              );
            },
          );
        },
      ),
    );
  }
}

class _AlbumGridTile extends StatefulWidget {
  const _AlbumGridTile({
    required this.path,
    required this.theme,
    required this.onTap,
  });

  final pm.AssetPathEntity path;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  State<_AlbumGridTile> createState() => _AlbumGridTileState();
}

class _AlbumGridTileState extends State<_AlbumGridTile> {
  late final Future<_AlbumPreview> _previewFuture =
      _loadAlbumPreview(widget.path);

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: FutureBuilder<_AlbumPreview>(
          future: _previewFuture,
          builder: (context, snap) {
            final preview = snap.data;
            final bytes = preview?.thumbBytes;
            final countLabel = preview == null ? '…' : '${preview.count}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: bytes != null && bytes.isNotEmpty
                      ? Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.photo_album_outlined,
                            size: 40,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.path.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        countLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
