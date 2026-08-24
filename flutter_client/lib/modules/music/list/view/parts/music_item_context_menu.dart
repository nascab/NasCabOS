import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../core/api/api_controller.dart';

class MusicItemContextMenu {
  static List<ContextMenuEntry> buildEntries({
    required bool selectionMode,
    required bool isFavorite,
    required bool inPlayList,
    required bool isSameMachine,
    required VoidCallback onFileBrowse,
    required VoidCallback onToggleFavorite,
    required VoidCallback onDownload,
    required VoidCallback onAddToPlayList,
    required VoidCallback onRemoveFromPlayList,
    required VoidCallback onDelete,
    VoidCallback? onOpen,
    VoidCallback? onProperty,
    VoidCallback? onShowInSystem,
    VoidCallback? onOpenInSystem,
  }) {
    if (selectionMode) return const <ContextMenuEntry>[];
    return [
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => onOpen?.call(),
      ),
      CustomContextMenuItem.create(
        label: Text('file_browse'.tr),
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        value: 'file_browse',
        onSelected: (_) => onFileBrowse(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text(isFavorite ? 'unfavorite'.tr : 'favorites'.tr),
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: isFavorite ? Colors.red : null,
        ),
        value: 'favorite',
        onSelected: (_) => onToggleFavorite(),
      ),
      CustomContextMenuItem.create(
        label: Text('download'.tr),
        icon: const Icon(Icons.download_outlined, size: 18),
        value: 'download',
        onSelected: (_) => onDownload(),
      ),
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('add_to_play_list'.tr),
        icon: const Icon(Icons.playlist_add, size: 18),
        value: 'add_to_play_list',
        onSelected: (_) => onAddToPlayList(),
      ),
      if (inPlayList)
        CustomContextMenuItem.create(
          label: Text('remove_from_play_list'.tr),
          icon: const Icon(Icons.playlist_remove, size: 18),
          value: 'remove_from_play_list',
          onSelected: (_) => onRemoveFromPlayList(),
        ),
      // 本机文件系统操作（仅桌面/Web端且客户端与服务端同机时显示）
      if (isSameMachine) ...[
        const MenuDivider(),
        CustomContextMenuItem.create(
          label: Text('file_show_in_folder'.tr),
          icon: const Icon(Icons.folder_open, size: 18),
          value: 'show_in_system',
          onSelected: (_) {
            if (!ApiController.instance.isServerVersionAtLeast(8)) {
              DialogUtil.showInfoDialog(
                title: 'tip'.tr,
                content: 'server_version_too_low'.tr,
              );
              return;
            }
            onShowInSystem?.call();
          },
        ),
        CustomContextMenuItem.create(
          label: Text('file_open_in_system'.tr),
          icon: const Icon(Icons.launch, size: 18),
          value: 'open_in_system',
          onSelected: (_) {
            if (!ApiController.instance.isServerVersionAtLeast(8)) {
              DialogUtil.showInfoDialog(
                title: 'tip'.tr,
                content: 'server_version_too_low'.tr,
              );
              return;
            }
            onOpenInSystem?.call();
          },
        ),
      ],
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text('delete'.tr, style: const TextStyle(color: Colors.red)),
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
        value: 'delete',
        onSelected: (_) => onDelete(),
      ),
    ];
  }

  static Widget region({
    required Widget child,
    required List<ContextMenuEntry> entries,
  }) {
    if (entries.isEmpty) return child;
    return ContextMenuUtil.region(child: child, entries: entries);
  }
}
