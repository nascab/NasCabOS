import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../controller/album_artist_list_controller.dart';
import '../../models/album_artist_list_models.dart';
import 'album_artist_list_item.dart';

class AlbumArtistListGrid extends StatelessWidget {
  final AlbumArtistListController controller;

  /// 由外层 Obx 订阅后传入，用于在网格 / 列表之间切换
  final String viewMode;
  final void Function(String name) onOpenSubList;
  const AlbumArtistListGrid({
    super.key,
    required this.controller,
    required this.viewMode,
    required this.onOpenSubList,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == 'list') {
      // 列表视图：SliverList 按需构建可视行
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, idx) {
          final item = controller.items[idx];
          final card = AlbumArtistItemCard(
            item: item,
            badgeLabel: controller.badgeLabel,
            width: double.infinity,
            coverSize: 52,
            layout: 'list',
            onTap: () => onOpenSubList(item.name),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _wrapWithMenu(context, item, card),
          );
        }, childCount: controller.items.length),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.crossAxisExtent;
        final desiredWidth = 150.0;
        final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 10);
        final spacing = 4.0;
        final totalSpacing = spacing * (crossAxisCount - 1);
        final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
            .floorToDouble();
        final coverSize = itemWidth * 0.98;
        final estimatedHeight = coverSize + 54;
        final aspectRatio = itemWidth / estimatedHeight;

        return SliverGrid(
          delegate: SliverChildBuilderDelegate((context, idx) {
            final item = controller.items[idx];
            final card = AlbumArtistItemCard(
              item: item,
              badgeLabel: controller.badgeLabel,
              width: itemWidth,
              coverSize: coverSize,
              onTap: () => onOpenSubList(item.name),
            );
            return _wrapWithMenu(context, item, card);
          }, childCount: controller.items.length),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
        );
      },
    );
  }

  List<ContextMenuEntry> _menuEntries(AlbumArtistGroupItem item) {
    return <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => onOpenSubList(item.name),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('add_to_play_list'.tr),
        icon: const Icon(Icons.playlist_add, size: 18),
        value: 'add_to_play_list',
        onSelected: (_) => controller.addToPlayList(item),
      ),
    ];
  }

  /// 桌面端用右键菜单，移动端用长按菜单
  Widget _wrapWithMenu(
    BuildContext context,
    AlbumArtistGroupItem item,
    Widget card,
  ) {
    final menuEntries = _menuEntries(item);
    if (DeviceUtils.isDesktop || DeviceUtils.isWeb) {
      return ContextMenuUtil.region(child: card, entries: menuEntries);
    }
    return GestureDetector(
      onLongPressStart: (d) {
        ContextMenuUtil.showAtPosition(
          context,
          entries: menuEntries,
          position: d.globalPosition,
        );
      },
      child: card,
    );
  }
}

class AlbumArtistListFooter extends StatelessWidget {
  final AlbumArtistListController controller;
  const AlbumArtistListFooter({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loadingMore.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Center(
          child: Text(
            'music_list_no_more'.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }

      if (!controller.autoLoadFailed.value) {
        return const SizedBox.shrink();
      }

      return Center(
        child: OutlinedButton(
          onPressed: () =>
              controller.loadMore(fromAuto: false).catchError((_) {}),
          child: Text('music_list_load_more'.tr),
        ),
      );
    });
  }
}
