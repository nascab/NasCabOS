import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/utils/dimens_util.dart';
import '../controllers/user_management_controller.dart';
import 'custom_user_form_dialog.dart';
import '../../base/components/custom_outlined_button.dart';

class CustomUserInfoCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final UserManagementController ctrl;
  const CustomUserInfoCard({super.key, required this.user, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = user['type']?.toString();
    final uid = (user['id'] as int?);
    return Card(
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['username']?.toString() ?? '',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 3),
                  decoration: BoxDecoration(
                    color: type == 'super_admin'
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "user_type_$type".tr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: DimensUtil.textSmall,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                CustomOutlinedButton(
                  icon: const Icon(Icons.edit, size: 18),
                  text: 'edit'.tr,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  borderColor: Theme.of(context).colorScheme.primary,
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => CustomUserFormDialog(
                        user: user,
                        onCreate: (u, p, {userRemark, phone}) async => false,
                        onUpdate:
                            (id, {username, password, userRemark, phone}) =>
                                ctrl.updateUser(
                                  id,
                                  username: username,
                                  password: password,
                                  userRemark: userRemark,
                                  phone: phone,
                                ),
                      ),
                    );
                    if ((ok ?? false)) ctrl.fetchUsers();
                  },
                ),
                // 删除按钮
                if (type != 'super_admin')
                  CustomOutlinedButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    text: 'delete'.tr,
                    foregroundColor: Theme.of(context).colorScheme.error,
                    borderColor: Theme.of(context).colorScheme.error,
                    onPressed: () async {
                      if (uid == null) return;

                      // 显示二次确认对话框
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: Text('need_confirm'.tr),
                          content: Text(
                            'user_delete_confirm_message'.trParams({
                              'username': user['username']?.toString() ?? '',
                            }),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text('cancel'.tr),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              child: Text('ok'.tr),
                            ),
                          ],
                        ),
                      );

                      if (confirmed ?? false) {
                        ctrl.selectedIds
                          ..clear()
                          ..add(uid);
                        await ctrl.deleteSelected();
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
