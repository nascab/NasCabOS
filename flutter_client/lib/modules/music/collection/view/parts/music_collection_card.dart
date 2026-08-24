import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../models/music_collection_model.dart';

class MusicCollectionCard extends StatelessWidget {
  final MusicCollectionItem collection;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MusicCollectionCard({
    super.key,
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

    final card = CustomAlbum(
      preview: MusicCollectionPreviewGrid(previews: collection.previews),
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

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      child: ContextMenuUtil.region(child: card, entries: entries),
    );
  }
}

class MusicCollectionPreviewGrid extends StatelessWidget {
  final List<MusicCollectionPreviewItem> previews;
  const MusicCollectionPreviewGrid({super.key, required this.previews});

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      return Image.asset(
        'assets/music/icons/default_cover.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    final items = previews.take(4).toList();
    Widget coverForPreview(MusicCollectionPreviewItem e) {
      if (e.hasInnerCover != 1) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      final filePath = (e.showType == 'series' ? e.firstFilePath : e.fullPath)
          .trim();
      if (filePath.isEmpty) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      final url = ApiController.instance.getMusicCoverUrl(
        filePath: filePath,
        size: 500,
      );
      if (url.isEmpty) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      return CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
        showLoading: false,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    Widget buildMainContent() {
      if (items.isEmpty) {
        return Image.asset(
          'assets/music/icons/default_cover.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
      final children = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        children.add(Expanded(child: coverForPreview(items[i])));
        if (i != items.length - 1) {
          children.add(const SizedBox(width: 1));
        }
      }
      return Row(children: children);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return buildMainContent();
      },
    );
  }
}
