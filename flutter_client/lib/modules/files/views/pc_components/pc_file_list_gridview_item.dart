import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../../base/components/custom_extended_image.dart';
import '../file_item_dot_hidden.dart';
import 'pc_internal_drag_item.dart';

/// 文件列表GridView项组件
class PcFileListGridViewItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final VoidCallback? onIconTap;

  const PcFileListGridViewItem({
    super.key,
    required this.item,
    this.onTap,
    this.onIconTap,
    required this.ctrl,
  });
  final PcFileExplorerController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final name = item['name']?.toString() ?? '';
      final filePath = item['path']?.toString() ?? '';
      final virtualType = item['virtualType']?.toString() ?? '';
      final isCustomPath = item['isCustomPath'] == true;
      final isSelected = ctrl.selected.contains(filePath);
      final type = item['type']?.toString() ?? '';
      final isUserShare = item['isUserShareFolder'] == true;
      final iconPath = virtualType == 'custom_add'
          ? 'assets/icons/file/folder_add.png'
          : (virtualType.isEmpty && isCustomPath && type == 'dir')
          ? 'assets/icons/file/folder_custom.png'
          : isUserShare
          ? 'assets/icons/file/folder_share.png'
          : ctrl.iconFor(name, filePath, type);
      final isAudioIcon = iconPath == 'assets/icons/file/audio.png';
      final isLargeGrid = ctrl.viewMode.value == 'large_grid';
      final iconSize = isLargeGrid ? 130.0 : 60.0;
      final textHeight = 35.0;
      final isSearching = ctrl.searchQuery.value.trim().isNotEmpty;
      final isDotHidden = fileItemIsDotHidden(item);
      return GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isDotHidden ? kFileHiddenListOpacity : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withValues(alpha: 0.2) : null,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  child: Center(
                    child: PcInternalIconDragHandle(
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
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      iconPath,
                                      width: iconSize,
                                      height: iconSize,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : SizedBox(
                                    width: iconSize * 1.5,
                                    height: iconSize,
                                    child: CustomExtendedImage(
                                      imageUrl: iconPath,
                                      fit: BoxFit.cover,
                                      borderRadius: 8,
                                    ),
                                  ),
                          ),
                          // 视频类型显示播放图标
                          if (type == 'video')
                            Container(
                              width: iconSize * 0.35,
                              height: iconSize * 0.35,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(
                                  iconSize * 0.175,
                                ),
                              ),
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: isLargeGrid ? 30 : 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: textHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: isSearching
                        ? Tooltip(
                            message: filePath,
                            waitDuration: const Duration(milliseconds: 200),
                            child: Text(
                              name,
                              maxLines: isLargeGrid ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.2),
                            ),
                          )
                        : Text(
                            name,
                            maxLines: isLargeGrid ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.2,
                              color: virtualType == 'custom_add'
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
