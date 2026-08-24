part of '../encrypted_space_view.dart';

class _EncryptedSpaceGridCard extends StatelessWidget {
  const _EncryptedSpaceGridCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onExport,
    required this.onRename,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final VoidCallback onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (item['space_name'] ?? '').toString().trim();
    final moreKey = GlobalKey();

    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        value: 'open',
        onSelected: (_) => onOpen(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('encrypted_space_export'.tr),
        icon: const Icon(Icons.file_download_outlined, size: 18),
        value: 'export',
        onSelected: (_) => onExport(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('rename'.tr),
        icon: const Icon(Icons.edit_outlined, size: 18),
        value: 'rename',
        onSelected: (_) => onRename(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        color: Colors.red,
        label: Text('delete'.tr),
        icon: const Icon(Icons.delete_outline, size: 18),
        value: 'delete',
        onSelected: (_) => onDelete(),
      ),
    ];

    final headerLeft = Row(
      children: [
        Flexible(
          child: Text(
            name.isEmpty ? 'name'.tr : name,
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

    final headerRight = IconButton(
      key: moreKey,
      tooltip: 'more'.tr,
      onPressed: () {
        final box = moreKey.currentContext?.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;
        final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
        ContextMenuUtil.showAtPosition(
          context,
          entries: entries,
          position: pos + Offset(0, box.size.height),
        );
      },
      icon: const Icon(Icons.more_vert, color: Colors.white),
    );

    final preview = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.lock_outline, size: 66, color: Colors.white),
      ),
    );

    Widget card = CustomAlbum(
      preview: preview,
      onTap: onOpen,
      headerLeft: headerLeft,
      headerRight: headerRight,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
    );

    if (!DeviceUtils.isDesktopOrWeb) return card;
    return ContextMenuUtil.region(child: card, entries: entries);
  }
}
