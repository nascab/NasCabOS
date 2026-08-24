import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import '../../transfer/views/file_log/file_log_item.dart';
import '../controllers/running_task_list_controller.dart';

/// Shows running file operations (processing + waiting) with progress and cancel.
/// Refreshes every 1s without loading indicator; auto-closes when list becomes empty.
void showRunningTaskListDialog(BuildContext context) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final ctx = Get.overlayContext ?? context;
    if (!ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => const RunningTaskListDialog(),
    ).then((_) {
      if (Get.isRegistered<RunningTaskListController>()) {
        Get.delete<RunningTaskListController>();
      }
    });
  });
}

class RunningTaskListDialog extends StatefulWidget {
  const RunningTaskListDialog({super.key});

  @override
  State<RunningTaskListDialog> createState() => _RunningTaskListDialogState();
}

class _RunningTaskListDialogState extends State<RunningTaskListDialog> {
  @override
  void initState() {
    super.initState();
    final c = Get.put(RunningTaskListController());
    c.setCloseCallback(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<RunningTaskListController>();
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.width < 400;
    final padding = isNarrow ? 12.0 : 20.0;
    final maxW = size.width > 100
        ? (size.width * 0.92).clamp(280.0, 520.0)
        : 520.0;
    final maxH = size.height > 100
        ? (size.height * 0.72).clamp(320.0, 520.0)
        : 420.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 24,
        vertical: isNarrow ? 16 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 14, padding, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'file_operation_running_title'.tr,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Obx(() {
                final logs = controller.logs;
                if (logs.isEmpty) {
                  return Center(child: Text('no_data'.tr));
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: padding - 4,
                  ),
                  itemCount: logs.length,
                  itemBuilder: (_, index) => FileLogItem(
                    log: logs[index],
                    onCancel: controller.cancelTask,
                    compact: isNarrow,
                  ),
                );
              }),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 10, padding, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'file_operation_task_running_hint'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CustomButton(
                        text: 'run_in_background'.tr,
                        onPressed: () => controller.closeDialog(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
