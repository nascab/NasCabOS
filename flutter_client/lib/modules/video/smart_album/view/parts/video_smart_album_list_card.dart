part of '../video_smart_album_list_view.dart';

class _SmartAlbumCard extends StatelessWidget {
  final VideoSmartAlbumController controller;
  final VideoSmartAlbumItem album;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SmartAlbumCard({
    required this.controller,
    required this.album,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final headerLeft = Row(
      children: [
        const Icon(Icons.filter_alt_outlined, color: Colors.white, size: 18),
        const SizedBox(width: 8),
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

    final preview = _SmartAlbumPreviewGrid(previews: album.previews);

    final card = CustomAlbum(
      preview: preview,
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

    final region = ContextMenuUtil.region(child: card, entries: entries);
    final tip = controller.buildAlbumTooltip(album);
    if (tip == null || tip.trim().isEmpty) return region;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: region,
    );
  }
}

class _SmartAlbumPreviewGrid extends StatelessWidget {
  final List<VideoSmartAlbumPreviewItem> previews;
  const _SmartAlbumPreviewGrid({required this.previews});

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      final theme = Theme.of(context);
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

    final urls = previews.take(4).map((e) {
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

    Widget buildImage(String url) {
      return CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
        showLoading: false,
      );
    }

    final children = <Widget>[];
    for (int i = 0; i < urls.length; i++) {
      children.add(Expanded(child: buildImage(urls[i])));
      if (i != urls.length - 1) {
        children.add(const SizedBox(width: 1));
      }
    }
    return Row(children: children);
  }
}
