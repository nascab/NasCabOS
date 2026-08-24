import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../controllers/mobile_upload_center_controller.dart';
import '../../controllers/upload_controller.dart';
import '../../models/transfer_task.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import 'app_upload_center/upload_center_completed_tab.dart';
import 'app_upload_center/upload_center_uploading_tab.dart';

class AppUploadCenterView extends StatefulWidget {
  const AppUploadCenterView({super.key, this.initialTargetDir});

  /// 从路由传入的上传目标目录（在 GetPage 的 page 回调中读取 Get.arguments，避免在子组件 initState 中读到上一次导航的参数）。
  final String? initialTargetDir;

  @override
  State<AppUploadCenterView> createState() => _AppUploadCenterViewState();
}

class _AppUploadCenterViewState extends State<AppUploadCenterView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final UploadController _uploadCtrl;
  late final MobileUploadCenterController _pageCtrl;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.enable());
    }
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(_onTabChanged);
    _uploadCtrl = Get.put(UploadController(), permanent: true);
    final boot = widget.initialTargetDir?.trim() ?? '';
    _pageCtrl = Get.put(
      MobileUploadCenterController(
        bootstrapTargetDir: boot.isEmpty ? null : boot,
      ),
    );
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    Get.delete<MobileUploadCenterController>();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.disable());
    }
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompletedTab = _tabController.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('home_quick_upload'.tr),
        actions: [
          if (isCompletedTab)
            Obx(() {
              final hasCompleted = _uploadCtrl.tasks.any(
                (t) =>
                    t.type == TransferType.upload &&
                    t.status == TransferStatus.completed,
              );
              if (!hasCompleted) return const SizedBox.shrink();
              return CustomBorderedIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'upload_center_clear_completed'.tr,
                onTap: () => _uploadCtrl.clearCompleted(),
              );
            }),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: 'task_uploading'.tr),
                Tab(text: 'task_completed'.tr),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                UploadCenterUploadingTab(
                  uploadCtrl: _uploadCtrl,
                  pageCtrl: _pageCtrl,
                ),
                UploadCenterCompletedTab(uploadCtrl: _uploadCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
