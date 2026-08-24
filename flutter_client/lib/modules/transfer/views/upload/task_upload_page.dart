import 'dart:async';
import 'dart:io' show Platform;

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/base/components/custom_divider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../controllers/upload_controller.dart';
import '../../models/transfer_task.dart';
import '../../../../utils/popup_menu_util.dart';
import 'task_upload_item.dart';

class TaskUploadPage extends StatefulWidget {
  const TaskUploadPage({super.key});

  @override
  State<TaskUploadPage> createState() => _TaskUploadPageState();
}

class _TaskUploadPageState extends State<TaskUploadPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Tab> _tabs = [];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.enable());
    }
    _tabs = [
      Tab(text: 'task_uploading'.tr),
      Tab(text: 'task_waitting'.tr),
      Tab(text: 'task_completed'.tr),
    ];
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
    final controller = Get.find<UploadController>();
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
                            'task_upload'.tr,
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
                      const SizedBox(height: 4),
                      Text(
                        '${'folder_name_strategy'.tr} : ${controller.nameStrategy.value.tr}',
                        style: const TextStyle(color: Colors.grey),
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
                // 清除任务菜单
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
                            value: 'waiting',
                            child: Text('task_clear_waiting'.tr),
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
                          case 'waiting':
                            controller.clearWaiting();
                            break;
                          case 'all':
                            controller.clearAll();
                            break;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (ctx) => CustomBorderedIconButton(
                    icon: Icons.rule,
                    tooltip: "folder_name_strategy".tr,
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
                          PopupMenuItem(value: 'skip', child: Text('skip'.tr)),
                          PopupMenuItem(
                            value: 'overwrite',
                            child: Text('overwrite'.tr),
                          ),
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('rename'.tr),
                          ),
                        ],
                      ).then((value) {
                        if (value == null) return;
                        final ctrl = Get.find<UploadController>();
                        ctrl.nameStrategy.value = value;
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
                    TransferStatus.error,
                  ].contains(task.status),
                ),
                _buildTaskList(
                  controller,
                  (task) => task.status == TransferStatus.pending,
                ),
                _buildTaskList(
                  controller,
                  (task) => task.status == TransferStatus.completed,
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
    UploadController controller,
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
              TaskUploadItem(task: task, controller: controller),
              if (!isLast) const CustomDivider(height: 8),
            ],
          );
        },
      );
    });
  }
}
