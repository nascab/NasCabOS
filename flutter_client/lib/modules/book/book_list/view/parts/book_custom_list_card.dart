import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../list/service/book_list_api_service.dart';
import '../../service/book_custom_list_api_service.dart';

class BookCustomListCard extends StatelessWidget {
  final BookCustomListItem item;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const BookCustomListCard({
    super.key,
    required this.item,
    required this.selectionMode,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ApiController>(
      builder: (_) {
        final theme = Theme.of(context);
        final preview = _buildPreviewGrid(context, item.previews);
        final moreKey = GlobalKey();
        final headerLeft = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        );

        Widget card = CustomAlbum(
          preview: preview,
          onTap: onOpen,
          headerPosition: CustomAlbumHeaderPosition.bottom,
          headerHeight: 50,
          headerLeft: headerLeft,
          headerRight: selectionMode
              ? null
              : IconButton(
                  key: moreKey,
                  tooltip: 'more'.tr,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () {
                    final box =
                        moreKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    final overlay =
                        Overlay.of(context).context.findRenderObject()
                            as RenderBox?;
                    if (box == null || overlay == null) return;
                    final pos = box.localToGlobal(
                      Offset.zero,
                      ancestor: overlay,
                    );
                    final entries = <ContextMenuEntry>[
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
                    ContextMenuUtil.showAtPosition(
                      context,
                      entries: entries,
                      position: pos + Offset(0, box.size.height),
                    );
                  },
                ),
          hoverEnabled: !selectionMode && DeviceUtils.isDesktopOrWeb,
        );

        if (!DeviceUtils.isDesktopOrWeb) return card;
        if (selectionMode) return card;

        final entries = <ContextMenuEntry>[
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
        return ContextMenuUtil.region(child: card, entries: entries);
      },
    );
  }

  Widget _buildPreviewGrid(BuildContext context, List<BookListItem> previews) {
    final items = previews.take(4).toList();
    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/book/bg_booklist.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
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

    Widget fallbackCover(BookListItem b) {
      final seed = b.fileHash.trim().isNotEmpty
          ? b.fileHash.trim()
          : b.fullPath.trim().isNotEmpty
          ? b.fullPath.trim()
          : b.firstFilePath.trim();
      final asset = fallbackAssets[stableIndex(seed)];
      return Image.asset(asset, fit: BoxFit.cover);
    }

    Widget buildCover(BookListItem b) {
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
              size: 350,
            )
          : (b.fullPath.trim().isNotEmpty
                ? ApiController.instance.getTinyUrl(b.fullPath)
                : '');

      return CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => fallbackCover(b),
      );
    }

    Widget preview;
    if (items.length == 1) {
      preview = buildCover(items.first);
    } else {
      final children = <Widget>[];
      for (int i = 0; i < items.length; i++) {
        children.add(Expanded(child: buildCover(items[i])));
        if (i != items.length - 1) {
          children.add(const SizedBox(width: 1));
        }
      }
      preview = Row(children: children);
    }

    return ClipRRect(borderRadius: BorderRadius.circular(10), child: preview);
  }
}
