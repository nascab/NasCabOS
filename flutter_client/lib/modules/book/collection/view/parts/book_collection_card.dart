import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../models/book_collection_model.dart';

class BookCollectionCard extends StatelessWidget {
  final BookCollectionItem collection;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const BookCollectionCard({
    super.key,
    required this.collection,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = collection.pathList.join('\n').trim();

    final headerLeft = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        collection.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Get.textTheme.titleMedium?.copyWith(color: Colors.white),
      ),
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
      preview: BookCollectionPreviewGrid(previews: collection.previews),
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

class BookCollectionPreviewGrid extends StatelessWidget {
  final List<BookCollectionPreviewItem> previews;
  const BookCollectionPreviewGrid({super.key, required this.previews});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ApiController>(
      builder: (_) {
        if (previews.isEmpty) {
          return Image.asset(
            'assets/book/bg_booklist.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }

        const fallbackAssets = <String>[
          'assets/icons/book/book_blue.jpg',
          'assets/icons/book/book_brown.jpg',
          'assets/icons/book/book_red.jpg',
          'assets/icons/book/book_green.jpg',
        ];

        int stableIndex(String seed) {
          if (seed.isEmpty) return 0;
          final h = seed.codeUnits.fold<int>(
            0,
            (p, e) => (p * 31 + e) & 0x7fffffff,
          );
          return h % fallbackAssets.length;
        }

        Widget fallbackCover(BookCollectionPreviewItem b) {
          final seed = b.fileHash.trim().isNotEmpty
              ? b.fileHash.trim()
              : b.fullPath.trim().isNotEmpty
              ? b.fullPath.trim()
              : b.firstFilePath.trim();
          final asset = fallbackAssets[stableIndex(seed)];
          return Image.asset(
            asset,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
        }

        Widget buildCover(BookCollectionPreviewItem b) {
          final isSeries = b.showType == 'series';
          final shouldFallback =
              b.coverState == 2 ||
              (isSeries
                  ? b.firstFilePath.trim().isEmpty
                  : (b.fileHash.trim().isEmpty && b.fullPath.trim().isEmpty));
          if (shouldFallback) return fallbackCover(b);

          final url = isSeries
              ? (b.firstFilePath.trim().isNotEmpty
                    ? ApiController.instance.getTinyUrl(b.firstFilePath)
                    : '')
              : b.fileHash.trim().isNotEmpty
              ? ApiController.instance.getBookTinyUrl(
                  fileHash: b.fileHash,
                  size: 500,
                )
              : (b.fullPath.trim().isNotEmpty
                    ? ApiController.instance.getTinyUrl(b.fullPath)
                    : '');

          if (url.trim().isEmpty) return fallbackCover(b);

          return CustomExtendedImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            borderRadius: 0,
            showLoading: false,
            errorBuilder: (context, error, stackTrace) => fallbackCover(b),
          );
        }

        Widget buildMainContent() {
          final items = previews.take(4).toList(growable: false);
          if (items.isEmpty) {
            return Image.asset(
              'assets/book/bg_booklist.jpg',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          }
          final children = <Widget>[];
          for (int i = 0; i < items.length; i++) {
            children.add(Expanded(child: buildCover(items[i])));
            if (i != items.length - 1) {
              children.add(const SizedBox(width: 1));
            }
          }
          return Row(children: children);
        }

        return LayoutBuilder(
          builder: (context, constraints) => buildMainContent(),
        );
      },
    );
  }
}
