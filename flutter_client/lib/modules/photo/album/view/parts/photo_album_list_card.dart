part of '../photo_album_list_view.dart';

class _AlbumCard extends StatelessWidget {
  final PhotoAlbumItem album;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AlbumCard({
    required this.album,
    required this.selectionMode,
    required this.onOpen,
    required this.onDownload,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final headerLeft = Row(
      children: [
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

    final publicBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_open, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            'public'.tr,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );

    final headerRight = selectionMode
        ? null
        : PopupMenuButton<String>(
            tooltip: '',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) {
              if (v == 'open') onOpen();
              if (v == 'download') onDownload();
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
              if (v == 'info') {
                final content = 'photo_album_creator_with_name'.trParams({
                  'name': album.ownerUsername ?? '',
                });
                DialogUtil.showInfoDialog(
                  title: 'info'.tr,
                  content: content,
                );
              }
            },
            itemBuilder: (_) {
              final items = <PopupMenuEntry<String>>[];
              items.add(
                PopupMenuItem<String>(value: 'open', child: Text('open'.tr)),
              );
              items.add(
                PopupMenuItem<String>(
                  value: 'download',
                  child: Text('download'.tr),
                ),
              );
              if (!album.isOwner) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'info',
                    child: Text('info'.tr),
                  ),
                );
              }
              if (album.isOwner) {
                items.add(
                  PopupMenuItem<String>(value: 'edit', child: Text('edit'.tr)),
                );
                items.add(
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('delete'.tr),
                  ),
                );
                // items.add(
                //   PopupMenuItem<String>(
                //     value: 'share',
                //     child: Text('photo_album_share_settings'.tr),
                //   ),
                // );
              }
              if (items.isEmpty) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'noop',
                    enabled: false,
                    child: Text('permission_denied'.tr),
                  ),
                );
              }
              return items;
            },
          );

    final card = CustomAlbum(
      preview: _AlbumPreviewGrid(previews: album.previews),
      onTap: onOpen,
      headerLeft: headerLeft,
      headerRight: headerRight,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
      overlayChildren: [
        if (album.isPublic) Positioned(left: 8, top: 8, child: publicBadge),
        if (selectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: CustomCheckbox(
              value: false,
              onChanged: (_) => onOpen(),
              isCircle: true,
              side: const BorderSide(color: Colors.white, width: 2),
            ),
          ),
      ],
    );

    final creatorTooltip = !album.isOwner && (album.ownerUsername != null && album.ownerUsername!.isNotEmpty)
        ? 'photo_album_creator_with_name'.trParams({'name': album.ownerUsername!})
        : null;

    Widget cardWidget = card;
    if (creatorTooltip != null) {
      cardWidget = Tooltip(
        message: creatorTooltip,
        child: card,
      );
    }

    if (selectionMode) return cardWidget;

    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => onOpen(),
      ),
      CustomContextMenuItem.create(
        label: Text('download'.tr),
        icon: const Icon(Icons.download_outlined, size: 18),
        value: 'download',
        onSelected: (_) => onDownload(),
      ),
      if (!album.isOwner)
        CustomContextMenuItem.create(
          label: Text('info'.tr),
          icon: const Icon(Icons.info_outline, size: 18),
          value: 'info',
          onSelected: (_) {
            final content = 'photo_album_creator_with_name'.trParams({
              'name': album.ownerUsername ?? '',
            });
            DialogUtil.showInfoDialog(
              title: 'info'.tr,
              content: content,
            );
          },
        ),
      if (album.isOwner) ...[
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
        // CustomContextMenuItem.create(
        //   label: Text('photo_album_share_settings'.tr),
        //   icon: const Icon(Icons.share_outlined, size: 18),
        //   value: 'share',
        //   onSelected: (_) => onShareSettings(),
        // ),
      ],
    ];

    return ContextMenuUtil.region(child: cardWidget, entries: entries);
  }
}

class _AlbumPreviewGrid extends StatelessWidget {
  final List<PhotoAlbumPreviewItem> previews;
  _AlbumPreviewGrid({required this.previews});

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      // 相册内无内容
      return CustomNoData(
        text: "",
        backgroundColorList: [Color(0xFF0061FF), Color(0xFF60EFFF)],
        imagePath: 'assets/icons/no_data.png',
      );
    }

    final urls = previews.take(4).map((e) {
      return ApiController.instance.getTinyUrl(e.fullpath);
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

    Widget preview;
    if (urls.length < 4) {
      preview = buildImage(urls.first);
    } else {
      preview = Column(
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

    return preview;
  }
}
