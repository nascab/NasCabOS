import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../list/models/music_list_models.dart';
import '../../service/play_list_api_service.dart';

class PlayListListCard extends StatelessWidget {
  final PlayListItem item;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const PlayListListCard({
    super.key,
    required this.item,
    required this.selectionMode,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _buildPreviewGrid(context, item.previews);
    final moreKey = GlobalKey();
    final headerLeft = Text(
      item.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    );

    Widget card = CustomAlbum(
      preview: preview,
      onTap: onOpen,
      headerLeft: headerLeft,
      headerHeight: 50,
      headerPosition: CustomAlbumHeaderPosition.bottom,
      headerRight: selectionMode
          ? null
          : IconButton(
              key: moreKey,
              tooltip: 'more'.tr,
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onPressed: () {
                final box =
                    moreKey.currentContext?.findRenderObject() as RenderBox?;
                final overlay =
                    Overlay.of(context).context.findRenderObject()
                        as RenderBox?;
                if (box == null || overlay == null) return;
                final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
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
  }

  Widget _buildPreviewGrid(BuildContext context, List<dynamic> previews) {
    final items = previews.take(4).toList();
    if (items.isEmpty) {
      return Image.asset(
        'assets/music/icons/default_cover.jpg',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    Widget fallbackCover(dynamic m) {
      final genre = (m.genre ?? '').toString().trim().toLowerCase();
      final parts = genre.split(RegExp(r'[\/,;|]')).map((e) => e.trim());
      final head = parts.isNotEmpty ? parts.first : '';
      final normalized = head.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final rng = Random((m.id as int?) ?? 0);
      const genreKeys = {
        'blues',
        'classical',
        'country',
        'gospel',
        'hiphop',
        'pop',
        'rock',
      };
      String assetPath;
      if (normalized.isNotEmpty && genreKeys.contains(normalized)) {
        final idx = rng.nextInt(6) + 1;
        assetPath = 'assets/music/musicCover/$normalized$idx.jpg';
      } else {
        final idx = rng.nextInt(20) + 1;
        assetPath = 'assets/music/musicCover/other$idx.jpg';
      }
      return Container(
        color: Theme.of(
          context,
        ).colorScheme.surfaceVariant.withValues(alpha: 0.4),
        child: Image.asset(
          assetPath,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    Widget buildCover(dynamic m) {
      final hasInnerCover = (m is MusicListItem)
          ? m.hasInnerCover
          : ((m.has_inner_cover as num?)?.toInt() ?? 0);
      if (hasInnerCover != 1) return fallbackCover(m);

      String coverFilePath = '';
      final showType = (m.showType ?? m.show_type ?? '').toString().trim();
      final isSeries = showType.toLowerCase() == 'series';
      if (isSeries) {
        coverFilePath = (m.firstFilePath ?? m.first_file_path ?? '')
            .toString()
            .trim();
      } else {
        coverFilePath = (m.fullPath ?? m.full_path ?? '').toString().trim();
        if (coverFilePath.isEmpty) {
          final base = (m.path ?? '').toString().trim();
          final name = (m.filename ?? '').toString().trim();
          coverFilePath = base.isNotEmpty && name.isNotEmpty
              ? '$base/$name'
              : base;
        }
      }

      if (coverFilePath.isNotEmpty) {
        final url = ApiController.instance.getMusicCoverUrl(
          filePath: coverFilePath,
          size: 500,
        );
        if (url.isNotEmpty) {
          return CustomExtendedImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            showLoading: false,
            borderRadius: 0,
            errorBuilder: (context, error, stackTrace) => fallbackCover(m),
          );
        }
      }

      return fallbackCover(m);
    }

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
      children.add(Expanded(child: buildCover(items[i])));
      if (i != items.length - 1) {
        children.add(const SizedBox(width: 1));
      }
    }
    return Row(children: children);
  }
}
