import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../service/file_api_service.dart';
import '../../../base/components.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../../home/views/pc_home_controller.dart';
import '../pc_file_browser.dart';

import 'package:intl/intl.dart';
import '../../service/file_stats_service.dart';
import '../../../../utils/file_util.dart';
import 'package:path/path.dart' as p;

class PcFileContextMenuHandler {
  static void showPropertiesDialog(List<String> paths) {
    final statsService = FileStatsService();
    final size = 0.obs;
    final fileCount = 0.obs;
    final folderCount = 0.obs;
    final isCalculating = true.obs;
    final ctime = Rxn<DateTime>();
    final mtime = Rxn<DateTime>();
    final name = RxnString();
    final path = RxnString();

    statsService.connect(
      paths: paths,
      onProgress: (stats) {
        size.value = stats.size;
        fileCount.value = stats.count;
        folderCount.value = stats.folderCount;
        if (stats.ctime != null) {
          ctime.value = stats.ctime;
        }
        if (stats.mtime != null) {
          mtime.value = stats.mtime;
        }
        if (stats.name != null && stats.name!.isNotEmpty) {
          name.value = stats.name;
        }
        if (stats.path != null && stats.path!.isNotEmpty) {
          path.value = stats.path;
        }
      },
      onComplete: (stats) {
        size.value = stats.size;
        fileCount.value = stats.count;
        folderCount.value = stats.folderCount;
        isCalculating.value = false;
      },
      onError: (err) {
        isCalculating.value = false;
      },
    );

    Get.dialog(
      AlertDialog(
        title: Text('property'.tr),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.value != null) Text('${'name'.tr}: ${name.value}'),
              if (path.value != null) Text('${'path'.tr}: ${path.value}'),
              if (name.value != null || path.value != null)
                const SizedBox(height: 10),

              Text('${'size'.tr}: ${FileUtil.formatSize(size.value)}'),
              Text(
                '${'contains'.tr}: ${'file_count_format'.trParams({'count': fileCount.value.toString()})}, ${'folder_count_format'.trParams({'count': folderCount.value.toString()})}',
              ),

              if (ctime.value != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${'create_time'.tr}: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(ctime.value!)}',
                ),
              ],
              if (mtime.value != null) ...[
                if (ctime.value == null) const SizedBox(height: 10),
                Text(
                  '${'modified_at'.tr}: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(mtime.value!)}',
                ),
              ],

              if (isCalculating.value) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              statsService.close();
              Get.back();
            },
            child: Text('ok'.tr),
          ),
        ],
      ),
    ).then((_) {
      statsService.close();
    });
  }

  static Future<void> show({
    required BuildContext context,
    required PcFileExplorerController ctrl,
    required Offset globalPosition,
    Map<String, dynamic>? hitItem,
  }) async {
    final virtualType = hitItem?['virtualType']?.toString() ?? '';
    if (virtualType.isNotEmpty) return;
    if (hitItem != null) {
      final path = hitItem['path']?.toString() ?? '';
      final type = hitItem['type']?.toString() ?? '';
      final isCustomPath = hitItem['isCustomPath'] == true;
      if (path.isNotEmpty) {
        if (!ctrl.selected.contains(path)) {
          ctrl.selectOnly(path);
        }
      }

      if (isCustomPath) {
        final entries = <ContextMenuEntry>[
          CustomContextMenuItem.create(
            label: Text('file_custom_path_remove'.tr),
            icon: const Icon(Icons.remove_circle_outline),
            value: 'custom_path_remove',
            onSelected: (_) async {
              if (path.trim().isEmpty) return;
              await ctrl.removeCustomPath(path);
            },
          ),
        ];

        await ContextMenuUtil.showAtPosition(
          context,
          entries: entries,
          position: globalPosition,
        );
        return;
      }

      final inFavoritesModule = ctrl.currentModule.value == 'favorites';
      final name = hitItem['name']?.toString() ?? '';
      final rawType = type.trim().toLowerCase();
      final pathExt = p.extension(path).replaceFirst('.', '').toLowerCase();
      final nameExt = p.extension(name).replaceFirst('.', '').toLowerCase();
      final isTxt = rawType == 'txt' || pathExt == 'txt' || nameExt == 'txt';
      final entries = <ContextMenuEntry>[
        CustomContextMenuItem.create(
          label: Text('open'.tr),
          icon: const Icon(Icons.open_in_new_outlined),
          value: 'open',
          onSelected: (_) async {
            final data = ctrl.displayItems;
            await ctrl.handleItemTap(hitItem, data, forceEnter: true);
          },
        ),
        if (isTxt && path.isNotEmpty)
          CustomContextMenuItem.create(
            label: Text('edit'.tr),
            icon: const Icon(Icons.edit_outlined),
            value: 'edit',
            onSelected: (_) async {
              await ctrl.openTextEditorForItem(hitItem);
            },
          ),
        if (type == 'dir' && path.isNotEmpty && DeviceUtils.isDesktop)
          CustomContextMenuItem.create(
            label: Text('open_in_new_window'.tr),
            icon: const Icon(Icons.open_in_new_outlined),
            value: 'open_in_new_window',
            onSelected: (_) {
              if (!Get.isRegistered<PcHomeController>()) return;
              final home = PcHomeController.instance;
              final windowId =
                  'folder_${DateTime.now().microsecondsSinceEpoch}';
              home.openApp(
                windowId: windowId,
                viewBuilder: (_) => PcFileBrowser(
                  initialPath: path,
                  listenHomeNavigateSignal: false,
                  windowId: windowId,
                ),
                title: 'app_folder'.tr,
                icon: home.buildAppIcon('folder'),
              );
            },
          ),
        CustomContextMenuItem.create(
          label: Text('quick_share_title'.tr),
          icon: const Icon(Icons.flash_on_outlined),
          value: 'quick_share',
          onSelected: (_) {
            final path = hitItem['path']?.toString() ?? '';
            if (path.trim().isEmpty) return;
            ctrl.openQuickShareCreateAt(path);
          },
        ),
        CustomContextMenuItem.create(
          label: Text('download'.tr),
          icon: const Icon(Icons.download_outlined),
          value: 'download',
          onSelected: (_) {
            final paths = ctrl.selected.toList();
            if (paths.isEmpty) return;
            // Ensure controller exists
            if (!Get.isRegistered<DownloadController>()) {
              Get.put(DownloadController(), permanent: true);
            }
            final hints = ctrl.remoteIsDirectoryHintsForPaths(paths);
            final hasAnyHint = hints.any((e) => e != null);
            Get.find<DownloadController>().handleDownload(
              paths,
              remoteIsDirectoryHint: hasAnyHint ? hints : null,
            );
          },
        ),
        CustomContextMenuItem.create(
          label: Text('folder_add_favorite'.tr),
          icon: const Icon(Icons.star),
          value: 'fav_add',
          onSelected: (_) async {
            final paths = ctrl.selected.toList();
            final ok = await ctrl.addFavorites(paths);
            if (ok) {
              ToastUtil.show('operation_success'.tr);
            } else {
              ToastUtil.show('operation_failed'.tr);
            }
          },
        ),
        const MenuDivider(),
        CustomContextMenuItem.create(
          label: Text('rename'.tr),
          icon: const Icon(Icons.drive_file_rename_outline),
          value: 'rename',
          onSelected: (_) async {
            final path = hitItem['path']?.toString() ?? '';
            final currentName = hitItem['name']?.toString() ?? '';
            if (path.isNotEmpty && currentName.isNotEmpty) {
              // 显示重命名对话框
              final newName = await DialogUtil.showInputDialog(
                title: 'rename'.tr,
                content: 'enter_new_name'.tr,
                initialValue: currentName,
                confirmText: 'ok'.tr,
                cancelText: 'cancel'.tr,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'name_cannot_be_empty'.tr;
                  }
                  return null;
                },
              );
              if (newName != null && newName != currentName) {
                await ctrl.renameEntry(path, newName);
              }
            }
          },
        ),
        CustomContextMenuItem.create(
          label: Text('file_copy'.tr),
          icon: const Icon(Icons.copy_outlined),
          value: 'copy',
          onSelected: (_) => ctrl.copyToClipboard(),
        ),
        CustomContextMenuItem.create(
          label: Text('file_cut'.tr),
          icon: const Icon(Icons.content_cut_outlined),
          value: 'cut',
          onSelected: (_) => ctrl.cutToClipboard(),
        ),

        if (!inFavoritesModule) ...[
          CustomContextMenuItem.create(
            label: Text('folder_action_copy_to'.tr),
            icon: const Icon(Icons.copy_outlined),
            value: 'copy_to',
            onSelected: (_) => ctrl.handleCopyOrMove(isCopy: true),
          ),
          CustomContextMenuItem.create(
            label: Text('folder_action_move_to'.tr),
            icon: const Icon(Icons.drive_file_move_outlined),
            value: 'move_to',
            onSelected: (_) => ctrl.handleCopyOrMove(isCopy: false),
          ),
        ],
        if (inFavoritesModule)
          CustomContextMenuItem.create(
            label: Text('unfavorite'.tr),
            icon: const Icon(Icons.star_outline_outlined),
            value: 'fav_remove',
            onSelected: (_) async {
              final paths = ctrl.selected.toList();
              final ok = await ctrl.removeFavorites(paths);
              if (ok) {
                ToastUtil.show('operation_success'.tr);
                await ctrl.refreshPage();
              } else {
                ToastUtil.show('operation_failed'.tr);
              }
            },
          ),
        CustomContextMenuItem.create(
          label: Text('delete'.tr),
          icon: const Icon(Icons.delete_outlined),
          color: Colors.red,
          value: 'delete',
          onSelected: (_) {
            // 检查是否支持shell
            final isShellSupported =
                ApiController.instance.state.shellSupported;
            print('isShellSupported: $isShellSupported');
            if (isShellSupported) {
              // 支持shell，显示三个按钮的对话框：取消、删除、放入系统回收站
              DialogUtil.showConfirmThreeButtonsDialog(
                title: 'need_confirm'.tr,
                content: 'folder_delete_confirm'.trParams({
                  'fileCount': ctrl.selected.length.toString(),
                }),
                option1Text: 'delete'.tr,
                option2Text: 'put_in_recycle_bin'.tr,
                onOption1: () => ctrl.deleteSelectedEntries(recycle: false),
                onOption2: () => ctrl.deleteSelectedEntries(recycle: true),
                option2IsPrimary: true,
              );
            } else {
              // 不支持shell，显示普通的确认对话框
              DialogUtil.showConfirmDialog(
                title: 'need_confirm'.tr,
                content: 'folder_delete_confirm'.trParams({
                  'fileCount': ctrl.selected.length.toString(),
                }),
                onConfirm: () => ctrl.deleteSelectedEntries(),
                confirmText: 'ok'.tr,
                cancelText: 'cancel'.tr,
              );
            }
          },
        ),
        //属性
        const MenuDivider(),
        // 本机文件系统操作（仅桌面/Web端且客户端与服务端同机时显示）
        if (DeviceUtils.isDesktopOrWeb &&
            ApiController.instance.isSameMachine) ...[
          if (type != 'dir')
            CustomContextMenuItem.create(
              label: Text('file_show_in_folder'.tr),
              icon: const Icon(Icons.folder_open_outlined),
              value: 'show_in_system',
              onSelected: (_) async {
                if (!ApiController.instance.isServerVersionAtLeast(8)) {
                  DialogUtil.showInfoDialog(
                    title: 'tip'.tr,
                    content: 'server_version_too_low'.tr,
                  );
                  return;
                }
                final res = await FileApiService.instance.showInSystem(path);
                if (!res.success) {
                  ToastUtil.show(res.message ?? 'operation_failed'.tr);
                }
              },
            ),
          CustomContextMenuItem.create(
            label: Text('file_open_in_system'.tr),
            icon: const Icon(Icons.launch_outlined),
            value: 'open_in_system',
            onSelected: (_) async {
              if (!ApiController.instance.isServerVersionAtLeast(8)) {
                DialogUtil.showInfoDialog(
                  title: 'tip'.tr,
                  content: 'server_version_too_low'.tr,
                );
                return;
              }
              final res = await FileApiService.instance.openInSystem(path);
              if (!res.success) {
                ToastUtil.show(res.message ?? 'operation_failed'.tr);
              }
            },
          ),
        ],
        CustomContextMenuItem.create(
          label: Text('property'.tr),
          icon: const Icon(Icons.info_outlined),
          value: 'properties',
          onSelected: (_) {
            final paths = ctrl.selected.toList();
            if (paths.isEmpty) return;
            showPropertiesDialog(paths);
          },
        ),
      ];

      await ContextMenuUtil.showAtPosition(
        context,
        entries: entries,
        position: globalPosition,
      );
    } else {
      final entries = <ContextMenuEntry>[
        CustomContextMenuItem.create(
          label: Text('refresh'.tr),
          icon: const Icon(Icons.refresh_outlined),
          value: 'refresh',
          onSelected: (_) {},
        ),
        CustomContextMenuItem.create(
          label: Text('folder_new_dir'.tr),
          icon: const Icon(Icons.create_new_folder_outlined),
          value: 'new_folder',
          onSelected: (_) async {
            final supported = await ctrl.ensureCreateFolderSupported();
            if (!supported) return;
            final name = await DialogUtil.showInputDialog(
              title: 'folder_new_dir'.tr,
              content: 'enter_new_name'.tr,
              confirmText: 'ok'.tr,
              cancelText: 'cancel'.tr,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'name_cannot_be_empty'.tr;
                }
                return null;
              },
            );
            if (name != null && name.isNotEmpty) {
              await ctrl.createFolder(name);
            }
          },
        ),

        // “最近”“收藏”列表不显示黏贴，不能作为黏贴目的地
        if (ctrl.clipboardItems.isNotEmpty &&
            ctrl.currentModule.value != 'recent' &&
            ctrl.currentModule.value != 'favorites') ...[
          CustomContextMenuItem.create(
            label: Text('file_paste'.tr),
            icon: const Icon(Icons.paste_outlined),
            value: 'paste',
            onSelected: (_) => ctrl.pasteFromClipboard(),
          ),
          CustomContextMenuItem.create(
            label: Text('folder_clean_clipboard'.tr),
            icon: const Icon(Icons.delete_outlined),
            value: 'clean_clipboard',
            onSelected: (_) => ctrl.clearClipboard(),
          ),
        ],
      ];
      final selected = await ContextMenuUtil.showAtPosition(
        context,
        entries: entries,
        position: globalPosition,
      );
      if (selected == 'refresh') {
        await ctrl.refreshPage();
      }
    }
  }
}
