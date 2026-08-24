part of '../photo_collection_list_view.dart';

class _CollectionCard extends StatelessWidget {
  final PhotoCollectionItem collection;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CollectionCard({
    required this.collection,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final paths = collection.pathList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tooltipMessage = paths.isEmpty
        ? 'no_path'.tr
        : '${'path'.tr}:\n${paths.join('\n')}';

    final headerLeft = Row(
      children: [
        Flexible(
          child: Text(
            collection.name,
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

    final preview = Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      preferBelow: false,
      child: _CollectionPreviewGrid(previews: collection.previews),
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

    return ContextMenuUtil.region(child: card, entries: entries);
  }
}
