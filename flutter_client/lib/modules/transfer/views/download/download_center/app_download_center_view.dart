import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../controllers/app_download_center_controller.dart';
import '../../../controllers/download_controller.dart';
import '../../../models/transfer_task.dart';
import '../task_download_item.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_no_data.dart';
import '../../../../base/components/custom_divider.dart';
import '../../../../base/views/app_base_page.dart';
import '../../../../../utils/toast_util.dart';

part 'parts/download_center_downloaded_files_tab.dart';
part 'parts/download_center_downloaded_file_item.dart';
part 'parts/download_center_task_tab.dart';
part 'parts/download_center_failed_tab.dart';

class AppDownloadCenterView extends StatefulWidget {
  const AppDownloadCenterView({super.key});

  @override
  State<AppDownloadCenterView> createState() => _AppDownloadCenterViewState();
}

class _AppDownloadCenterViewState extends State<AppDownloadCenterView> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.enable());
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    final controller = Get.put(AppDownloadCenterController());

    return DefaultTabController(
      length: 3,
      child: AppBasePage(
        title: 'home_download_center'.tr,
        actions: [
          Obx(
            () => CustomBorderedIconButton(
              tooltip: 'download_history_clear_title'.tr,
              onTap: controller.isRefreshingFiles.value
                  ? null
                  : () async {
                      final hasActive = controller.downloadController.tasks.any(
                        (t) =>
                            t.type == TransferType.download &&
                            (t.status == TransferStatus.uploading ||
                                t.status == TransferStatus.pending),
                      );
                      if (hasActive) {
                        ToastUtil.show('download_center_stop_tasks_first'.tr);
                        return;
                      }
                      await controller.promptClearAllHistory();
                    },
              icon: Icons.delete_sweep_outlined,
            ),
          ),
          SizedBox(width: 8),
          Obx(
            () => CustomBorderedIconButton(
              tooltip: 'refresh'.tr,
              enabled: !controller.isRefreshingFiles.value,
              onTap: controller.isRefreshingFiles.value
                  ? null
                  : controller.refreshDownloadedFiles,
              icon: Icons.refresh,
            ),
          ),
        ],
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: TabBar(
                tabs: [
                  Tab(text: 'task_downloading'.tr),
                  Tab(text: 'task_failed'.tr),
                  Tab(text: 'task_completed'.tr),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _DownloadCenterTaskTab(),
                  const _DownloadCenterFailedTab(),
                  const _DownloadCenterDownloadedFilesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
