import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/upload_controller.dart';
import '../../../models/transfer_task.dart';

class UploadCenterCompletedTab extends StatelessWidget {
  const UploadCenterCompletedTab({super.key, required this.uploadCtrl});

  final UploadController uploadCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final list =
          uploadCtrl.tasks
              .where(
                (t) =>
                    t.type == TransferType.upload &&
                    t.status == TransferStatus.completed,
              )
              .toList()
            ..sort((a, b) => b.createdTime.compareTo(a.createdTime));

      if (list.isEmpty) {
        return CustomNoData(text: 'task_empty'.tr);
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final task = list[index];
          final savedPath = _joinRemotePath(task.remotePath, task.name);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  ToastUtil.show(savedPath);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              savedPath,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      CustomBorderedIconButton(
                        tooltip: 'delete'.tr,
                        onTap: () => uploadCtrl.deleteTask(task),
                        icon: Icons.delete_outline,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  String _joinRemotePath(String dir, String name) {
    final d = dir.trim().isEmpty ? '/' : dir.trim();
    if (d.endsWith('/')) return '$d$name';
    return '$d/$name';
  }
}
