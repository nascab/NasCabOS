part of '../photo_smart_album_list_view.dart';

class _SmartAlbumCard extends StatelessWidget {
  final PhotoSmartAlbumController controller;
  final PhotoSmartAlbumItem album;
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
        Icon(_typeIcon(album.type), color: Colors.white, size: 18),
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

    final preview = _SmartAlbumPreviewGrid(
      previews: album.previews,
      fallbackColors: _typeColors(album.type),
      fallbackIcon: _typeIcon(album.type),
    );

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

  IconData _typeIcon(String type) {
    if (type == 'smart_date') return Icons.event_available_outlined;
    return Icons.filter_alt_outlined;
  }

  List<Color> _typeColors(String type) {
    if (type == 'smart_date') {
      return const [Color(0xFF0061FF), Color(0xFF60EFFF)];
    }
    return const [Color(0xFF8E2DE2), Color(0xFF4A00E0)];
  }
}

class _SmartAlbumPreviewGrid extends StatelessWidget {
  final List<PhotoSmartAlbumPreviewItem> previews;
  final List<Color> fallbackColors;
  final IconData fallbackIcon;

  const _SmartAlbumPreviewGrid({
    required this.previews,
    required this.fallbackColors,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: fallbackColors,
          ),
        ),
        child: Center(
          child: Icon(
            fallbackIcon,
            size: 60,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      );
    }

    final urls = previews
        .take(4)
        .map((e) {
          return ApiController.instance.getTinyUrl(e.fullpath);
        })
        .where((e) => e.isNotEmpty)
        .toList();

    if (urls.isEmpty) {
      return CustomNoData(text: "");
    }

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

    if (urls.length < 4) {
      return buildImage(urls.first);
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: buildImage(urls[0])),
              Expanded(child: buildImage(urls[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: buildImage(urls[2])),
              Expanded(child: buildImage(urls[3])),
            ],
          ),
        ),
      ],
    );
  }
}
