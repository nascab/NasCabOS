import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../pc_home_controller.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../base/components.dart';
import '../components/user_info_dialog.dart';
import '../../../fileBackup/localBackup/local_backup_controller.dart';
import '../../../fileBackup/serverBackup/file_backup_controller.dart';
import '../../../transfer/controllers/upload_controller.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../../transfer/models/transfer_task.dart';

class PcDockBar extends StatelessWidget {
  const PcDockBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = PcHomeController.instance;

    return Obx(() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
        child: CustomGlassContainer(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 备份运行中时在顶部显示 beat 动画，点击打开备份应用并切到本地备份
                  _buildBackupRunningIndicator(context, ctrl),

                  //我的账号
                  _dockIcon(
                    context,
                    Icons.account_box_outlined,
                    'my_account'.tr,
                    () {
                      Get.dialog(const UserInfoDialog());
                    },
                  ),
                  _divider(theme),
                  _dockIcon(
                    context,
                    Icons.app_registration_rounded,
                    'home_dock_all_apps'.tr,
                    () {
                      ctrl.toggleAllAppsOverlay(true);
                    },
                  ),
                  _divider(theme),
                  _dockIcon(
                    context,
                    Icons.computer_outlined,
                    'home_dock_show_desktop'.tr,
                    size: 24,
                    () {
                      final apps = List<String>.from(ctrl.openedApps);
                      for (final app in apps) {
                        ctrl.minimizeApp(app);
                      }
                    },
                  ),
                  _divider(theme),
                  _taskCenterDockIcon(theme, ctrl),
                  _divider(theme),
                  _dockIcon(
                    context,
                    Icons.notifications_outlined,
                    'message_center'.tr,
                    size: 26,
                    () {
                      ctrl.openApp(
                        windowId: 'message_center',
                        viewBuilder: ctrl.builtinAppViewBuilder(
                          'message_center',
                        ),
                      );
                    },
                  ),
                  if (ctrl.dockApps.isNotEmpty) _divider(theme),
                  if (ctrl.dockApps.isNotEmpty)
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      itemBuilder: (c, i) {
                        final windowId = ctrl.dockApps[i];
                        return _dockAppIcon(context, windowId, () {
                          if (ctrl.minimizedApps.contains(windowId)) {
                            ctrl.restoreFromDock(windowId);
                          } else {
                            //如果已经在顶部了，则直接缩小 否则移动到顶部
                            if (ctrl.topmostApp == windowId) {
                              ctrl.minimizeApp(windowId);
                            } else {
                              ctrl.focusWindow(windowId);
                            }
                          }
                        });
                      },
                      separatorBuilder: (c, i) => const SizedBox(height: 8),
                      itemCount: ctrl.dockApps.length,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBackupRunningIndicator(
    BuildContext context,
    PcHomeController pcCtrl,
  ) {
    if (!Get.isRegistered<LocalBackupController>()) {
      return const SizedBox.shrink();
    }
    final lbCtrl = Get.find<LocalBackupController>();
    final theme = Theme.of(context);
    return Obx(() {
      final running = lbCtrl.profiles.any(
        (p) => lbCtrl.runtimeOf(p.id).busy.value,
      );
      if (!running) {
        return const SizedBox.shrink();
      }
      return Tooltip(
        message: 'local_backup_running_tooltip'.tr,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            pcCtrl.openApp(
              windowId: 'backup',
              viewBuilder: pcCtrl.builtinAppViewBuilder('backup'),
              title: 'app_backup'.tr,
              icon: pcCtrl.buildAppIcon('backup'),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Get.isRegistered<FileBackupController>()) {
                Get.find<FileBackupController>().selectPage('backup.local');
              }
            });
          },
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: LoadingAnimationWidget.beat(
                  color: Colors.white,
                  size: 20,
                ),
              ),
              _divider(theme),
            ],
          ),
        ),
      );
    });
  }

  /// 上传/下载队列中存在进行中或排队任务（控制器未注册时视为无任务）。
  static bool _transferTasksActive() {
    if (Get.isRegistered<UploadController>()) {
      final list = Get.find<UploadController>().tasks;
      for (final t in list) {
        if (t.isCalculatingHash ||
            t.status == TransferStatus.uploading ||
            t.status == TransferStatus.pending) {
          return true;
        }
      }
    }
    if (Get.isRegistered<DownloadController>()) {
      final list = Get.find<DownloadController>().tasks;
      for (final t in list) {
        if (t.status == TransferStatus.uploading ||
            t.status == TransferStatus.pending) {
          return true;
        }
      }
    }
    return false;
  }

  Widget _taskCenterDockIcon(ThemeData theme, PcHomeController ctrl) {
    final active = _transferTasksActive();
    return Tooltip(
      message: 'app_task_center'.tr,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ctrl.openApp(
            windowId: 'task_center',
            viewBuilder: ctrl.builtinAppViewBuilder('task_center'),
            title: 'app_task_center'.tr,
            icon: ctrl.buildAppIcon('task_center'),
          );
        },
        child: Container(
          width: 44,
          alignment: Alignment.center,
          child: active
              ? LoadingAnimationWidget.inkDrop(color: Colors.white, size: 20)
              : Icon(Icons.sync_outlined, size: 28, color: Colors.white),
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Container(
      width: 40,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white24,
    );
  }

  Widget _dockIcon(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    double size = 28,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 44,
          alignment: Alignment.center,
          child: Icon(icon, size: size, color: Colors.white),
        ),
      ),
    );
  }

  Widget _dockAppIcon(
    BuildContext context,
    String windowId,
    VoidCallback onTap,
  ) {
    final ctrl = PcHomeController.instance;
    final tooltip = (ctrl.windowTitle(windowId) ?? '').trim().isEmpty
        ? windowId
        : ctrl.windowTitle(windowId)!.trim();
    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('home_window_close'.tr),
        icon: const Icon(Icons.close_outlined),
        value: 'quit',
        onSelected: (_) {
          ctrl.closeApp(windowId);
        },
      ),
      CustomContextMenuItem.create(
        label: Text('close_all'.tr),
        icon: const Icon(Icons.cancel_outlined),
        value: 'quit_all',
        onSelected: (_) {
          // 关闭dock中所有程序
          final apps = List<String>.from(ctrl.dockApps);
          for (final app in apps) {
            ctrl.closeApp(app);
          }
        },
      ),
    ];

    return Tooltip(
      message: tooltip,
      child: ContextMenuUtil.region(
        entries: entries,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child:
                            ctrl.windowIcon(windowId) ??
                            Icon(
                              Icons.apps_outlined,
                              size: 22,
                              color: Colors.white,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (PcHomeController.instance.minimizedApps.contains(
                    windowId,
                  ))
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white54,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    Container(
                      width: 20,
                      height: 2,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
