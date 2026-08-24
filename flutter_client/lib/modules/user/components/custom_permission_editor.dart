import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/custom_permission_editor_controller.dart';

class CustomPermissionEditor extends StatelessWidget {
  final List<Map<String, dynamic>> initial;
  final Future<bool> Function(List<Map<String, dynamic>> permissions) onSave;
  final Future<void> Function(void Function(String path) onSelected)
  onPickDirectory;

  // 使用Key来唯一标识每个编辑器实例
  const CustomPermissionEditor({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onPickDirectory,
  });

  @override
  Widget build(BuildContext context) {
    // 使用Get.create确保控制器在每次使用时都重新创建，但保持状态一致性
    return GetBuilder<CustomPermissionEditorController>(
      init: CustomPermissionEditorController(
        initialPermissions: initial,
        onSave: onSave,
        onPickDirectory: onPickDirectory,
      ),
      builder: (ctrl) {
        var theme = Theme.of(context);
        return ListView.builder(
          itemCount: ctrl.items.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              // 添加授权目录card
              return Card(
                color: theme.cardColor,
                child: ListTile(
                  leading: const Icon(Icons.add),
                  title: Text('user_mgmt_add_auth_dir'.tr),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'user_mgmt_add_auth_dir_alert'.tr,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      Text(
                        'user_mgmt_add_auth_dir_hint'.tr,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await ctrl.pickDirectory();
                  },
                ),
              );
            }
            final it = ctrl.items[i - 1];
            return Card(
              color: theme.cardColor,
              child: ListTile(
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        ctrl.removePermission(i - 1);
                      },
                    ),
                    Expanded(
                      child: Text(
                        (it['res_path'] ?? '').toString(),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ).paddingOnly(bottom: 8),
                subtitle: Wrap(
                  spacing: 8,
                  children: [
                    _actionChip(ctrl, i - 1, 'view', 'perm_view'.tr),
                    _actionChip(ctrl, i - 1, 'download', 'download'.tr),
                    _actionChip(ctrl, i - 1, 'update', 'perm_update'.tr),
                    _actionChip(ctrl, i - 1, 'delete', 'perm_delete'.tr),
                    _actionChip(ctrl, i - 1, 'upload', 'upload'.tr),
                    _actionChip(ctrl, i - 1, 'share', 'share'.tr),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _actionChip(
    CustomPermissionEditorController ctrl,
    int idx,
    String action,
    String label,
  ) {
    final it = ctrl.items[idx];
    final List<String> acts = List<String>.from(it['actions'] ?? <String>[]);
    final selected = acts.contains(action);
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.comfortable,
      padding: EdgeInsets.all(4),
      labelPadding: EdgeInsets.symmetric(horizontal: 2),
      onSelected: (_) {
        ctrl.toggleAction(idx, action);
      },
    );
  }
}
