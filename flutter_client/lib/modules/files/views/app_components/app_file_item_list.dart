import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/file_util.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../controllers/app_file_controller.dart';
import 'app_file_item_menu.dart';
import 'app_file_thumb.dart';
import '../file_item_dot_hidden.dart';

class AppFileListItem extends StatelessWidget {
  const AppFileListItem({
    super.key,
    required this.ctrl,
    required this.item,
    required this.allItems,
    required this.onOpenDir,
  });

  final AppFileController ctrl;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> allItems;
  final Future<void> Function(String path, String folderName) onOpenDir;

  String _listSubtitleLine() {
    final fileType = item['type']?.toString() ?? '';
    final mtimeText = ctrl.formatMtime(item['mtimeMs'] as num?);
    if (fileType == 'dir') return mtimeText;
    final raw = item['size'];
    int? bytes;
    if (raw is int) {
      bytes = raw;
    } else if (raw is num) {
      bytes = raw.toInt();
    }
    if (bytes == null || bytes < 0) return mtimeText;
    return '$mtimeText · ${FileUtil.formatSize(bytes)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = item['path']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final type = item['type']?.toString() ?? '';
    final virtualType = item['virtualType']?.toString() ?? '';
    final isCustomPath = item['isCustomPath'] == true;
    final isCustomAdd = virtualType == 'custom_add';
    final isDotHidden = fileItemIsDotHidden(item);

    return Obx(() {
      final isMultiSelect = ctrl.isMultiSelectMode.value;
      final isSelected = isMultiSelect && ctrl.selected.contains(path);
      return Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (isCustomAdd) {
              await ctrl.handleItemTap(item, allItems, forceEnter: true);
              return;
            }
            if (isMultiSelect) {
              ctrl.toggleSelect(path);
              return;
            }
            if (type == 'dir') {
              await onOpenDir(path, name);
              return;
            }
            await ctrl.handleItemTap(item, allItems, forceEnter: true);
          },
          onLongPress: isCustomAdd
              ? null
              : () {
                  if (!isMultiSelect) {
                    ctrl.enterMultiSelectMode(path);
                    return;
                  }
                  ctrl.toggleSelect(path);
                },
          child: Opacity(
            opacity: isDotHidden ? kFileHiddenListOpacity : 1.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (isMultiSelect && !isCustomAdd) ...[
                    SizedBox(
                      width: 34,
                      child: Center(
                        child: CustomCheckbox(
                          value: isSelected,
                          onChanged: (_) => ctrl.toggleSelect(path),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AppFileThumb(
                    ctrl: ctrl,
                    name: name,
                    type: type,
                    path: path,
                    size: 42,
                    virtualType: virtualType,
                    isCustomPath: isCustomPath,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isCustomAdd
                                      ? theme.colorScheme.primary
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (!isCustomAdd)
                                Text(
                                  _listSubtitleLine(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!isMultiSelect && !isCustomAdd) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => showAppFileItemMenuBottomSheet(
                              context,
                              ctrl: ctrl,
                              item: item,
                              allItems: allItems,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 6),
                              child: Icon(
                                Icons.more_vert_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
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
