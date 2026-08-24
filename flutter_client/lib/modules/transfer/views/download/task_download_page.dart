import 'dart:async';
import 'dart:io' show Platform;

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../controllers/download_controller.dart';
import '../../models/transfer_task.dart';
import '../../../base/components/custom_divider.dart';
import '../../../../utils/popup_menu_util.dart';
import 'task_download_item.dart';

class TaskDownloadPage extends StatefulWidget {
  const TaskDownloadPage({super.key});

  @override
  State<TaskDownloadPage> createState() => _TaskDownloadPageState();
}

class _TaskDownloadPageState extends State<TaskDownloadPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<Tab> _tabs;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.enable());
    }
    _tabs = [Tab(text: 'task_downloading'.tr), Tab(text: 'task_completed'.tr)];
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: 0,
    );
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.disable());
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure controller is found (it should be put by parent or binding)
    final controller = Get.find<DownloadController>();
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();

    return Container(
      decoration: BoxDecoration(
        color: customColors?.mainContentBgColor,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Obx(
                  () => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'task_download'.tr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'task_count'.trParams({
                              'count': controller.tasks.length.toString(),
                            }),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Pause All
                CustomBorderedIconButton(
                  tooltip: 'task_pause_all'.tr,
                  onTap: controller.pauseAll,
                  icon: Icons.pause_circle_outline,
                ),
                const SizedBox(width: 8),
                // Start All
                CustomBorderedIconButton(
                  tooltip: 'task_start_all'.tr,
                  onTap: controller.startAll,
                  icon: Icons.play_circle_outline,
                ),
                const SizedBox(width: 8),
                // Clear Menu
                Builder(
                  builder: (ctx) => CustomBorderedIconButton(
                    icon: Icons.delete_sweep,
                    tooltip: 'task_clear_all'.tr,
                    onTap: () {
                      final renderBox = ctx.findRenderObject() as RenderBox;
                      final offset = renderBox.localToGlobal(Offset.zero);
                      final size = renderBox.size;
                      PopupMenuUtil.showBelowContent<String>(
                        context: ctx,
                        position: RelativeRect.fromLTRB(
                          offset.dx,
                          offset.dy + size.height + 4,
                          offset.dx + size.width,
                          offset.dy + size.height + 4,
                        ),
                        items: [
                          PopupMenuItem(
                            value: 'completed',
                            child: Text('task_clear_completed'.tr),
                          ),
                          PopupMenuItem(
                            value: 'error',
                            child: Text('task_clear_error'.tr),
                          ),
                          PopupMenuItem(
                            value: 'all',
                            child: Text('task_clear_all'.tr),
                          ),
                        ],
                      ).then((value) {
                        if (value == null) return;
                        switch (value) {
                          case 'completed':
                            controller.clearCompleted();
                            break;
                          case 'error':
                            controller.clearError();
                            break;
                          case 'all':
                            controller.confirmClearAll();
                            break;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const CustomDivider(height: 1),
          TabBar(
            controller: _tabController,
            tabs: _tabs,
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface,
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            dividerHeight: 0.0,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(
                  controller,
                  (task) => [
                    TransferStatus.uploading,
                    TransferStatus.paused,
                    TransferStatus.pending,
                  ].contains(task.status),
                ),
                _buildTaskList(
                  controller,
                  (task) => [
                    TransferStatus.completed,
                    TransferStatus.error,
                  ].contains(task.status),
                  limit: 500,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(
    DownloadController controller,
    bool Function(TransferTask) filter, {
    int? limit,
  }) {
    return Obx(() {
      final filteredTasks = controller.tasks.where(filter).toList();
      List<TransferTask> tasks = filteredTasks;
      if (limit != null && tasks.length > limit) {
        tasks = List.from(tasks)
          ..sort((a, b) => b.createdTime.compareTo(a.createdTime))
          ..take(limit).toList();
      }
      final reversedTasks = tasks.reversed.toList();

      if (reversedTasks.isEmpty) {
        return CustomNoData(text: 'task_empty'.tr);
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        itemCount: reversedTasks.length,
        itemBuilder: (context, index) {
          final task = reversedTasks[index];
          final isLast = index == reversedTasks.length - 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TaskDownloadItem(task: task, controller: controller),
              if (!isLast) const CustomDivider(height: 8),
            ],
          );
        },
      );
    });
  }
}
