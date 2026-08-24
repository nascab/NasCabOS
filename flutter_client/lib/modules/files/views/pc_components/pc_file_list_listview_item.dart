import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../../utils/file_util.dart';
import '../file_item_dot_hidden.dart';
import 'pc_internal_drag_item.dart';

/// 文件列表ListView项组件
class PcFileListListViewItem extends StatelessWidget {
  final PcFileExplorerController ctrl;
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onIconTap;

  const PcFileListListViewItem({
    super.key,
    required this.item,
    this.onTap,
    this.onIconTap,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = item['name']?.toString() ?? '';
    final filePath = item['path']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    final virtualType = item['virtualType']?.toString() ?? '';
    final isCustomPath = item['isCustomPath'] == true;
    final isUserShare = item['isUserShareFolder'] == true;
    final iconPath = virtualType == 'custom_add'
        ? 'assets/icons/file/folder_add.png'
        : (virtualType.isEmpty && isCustomPath && type == 'dir')
        ? 'assets/icons/file/folder_custom.png'
        : isUserShare
        ? 'assets/icons/file/folder_share.png'
        : ctrl.iconFor(name, filePath, type);
    final iconSize = 35.0;
    return Obx(() {
      final isSelected = ctrl.selected.contains(filePath);
      final isAudioIcon = iconPath == 'assets/icons/file/audio.png';
      final isSearching = ctrl.searchQuery.value.trim().isNotEmpty;
      final isDotHidden = fileItemIsDotHidden(item);
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: isDotHidden ? kFileHiddenListOpacity : 1.0,
          child: Container(
            height: PcFileExplorerController.kListViewRowHeight,
            width: double.infinity,
            color: isSelected ? Colors.blue.withValues(alpha: 0.2) : null,
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall,
              child: Row(
                children: [
                  SizedBox(
                    width: ctrl.columnWidths['name'] ?? 300,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        PcInternalIconDragHandle(
                          ctrl: ctrl,
                          item: item,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              GestureDetector(
                                onTap: isAudioIcon ? onIconTap : null,
                                behavior: isAudioIcon
                                    ? HitTestBehavior.opaque
                                    : HitTestBehavior.deferToChild,
                                child: iconPath.startsWith('assets')
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.asset(
                                          iconPath,
                                          width: iconSize,
                                          height: iconSize,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : SizedBox(
                                        width: iconSize,
                                        height: iconSize,
                                        child: CustomExtendedImage(
                                          imageUrl: iconPath,
                                          fit: BoxFit.cover,
                                          borderRadius: 4,
                                        ),
                                      ),
                              ),
                              // 视频类型显示播放图标
                              if (type == 'video')
                                Container(
                                  width: iconSize * 0.4,
                                  height: iconSize * 0.4,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(
                                      iconSize * 0.2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: isSearching
                              ? Tooltip(
                                  message: filePath,
                                  waitDuration: const Duration(
                                    milliseconds: 200,
                                  ),
                                  child: Text(
                                    name,
                                    style: virtualType == 'custom_add'
                                        ? theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.primary,
                                          )
                                        : null,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : Text(
                                  name,
                                  style: virtualType == 'custom_add'
                                      ? theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: ctrl.columnWidths['mtime'] ?? 160,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        ctrl.formatMtime(item['mtimeMs'] as num?),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: ctrl.columnWidths['size'] ?? 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item['size'] != null
                            ? FileUtil.formatSize(item['size'] as int?)
                            : '-',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: ctrl.columnWidths['type'] ?? 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        ctrl.getFileTypeStr(type),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
