import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../controllers/app_file_controller.dart';
import 'app_file_item_menu.dart';
import 'app_file_thumb.dart';
import '../file_item_dot_hidden.dart';

class AppFileGridItem extends StatelessWidget {
  const AppFileGridItem({
    super.key,
    required this.ctrl,
    required this.item,
    required this.allItems,
    required this.large,
    required this.onOpenDir,
  });

  final AppFileController ctrl;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> allItems;
  final bool large;
  final Future<void> Function(String path, String folderName) onOpenDir;

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
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
          child: Stack(
            children: [
              Opacity(
                opacity: isDotHidden ? kFileHiddenListOpacity : 1.0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.10)
                        : theme.colorScheme.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.6)
                          : isCustomAdd
                          ? theme.colorScheme.primary.withValues(alpha: 0.4)
                          : theme.dividerColor,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: AppFileThumb(
                          ctrl: ctrl,
                          name: name,
                          type: type,
                          path: path,
                          size: large ? 128 : 80,
                          virtualType: virtualType,
                          isCustomPath: isCustomPath,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCustomAdd ? theme.colorScheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: isCustomAdd
                                ? const SizedBox.shrink()
                                : Text(
                                    ctrl.formatMtime(item['mtimeMs'] as num?),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                          if (!isMultiSelect && !isCustomAdd)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => showAppFileItemMenuBottomSheet(
                                context,
                                ctrl: ctrl,
                                item: item,
                                allItems: allItems,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.more_vert_outlined,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isMultiSelect && !isCustomAdd)
                Positioned(
                  top: 2,
                  right: 2,
                  child: CustomCheckbox(
                    value: isSelected,
                    onChanged: (_) => ctrl.toggleSelect(path),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
