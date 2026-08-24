import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// ignore: unused_import
import 'package:cross_file/cross_file.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../../transfer/controllers/upload_controller.dart';
import '../../../base/components/custom_glass_card.dart';
import 'pc_file_list_operation_bar.dart';
import 'pc_file_list.dart';
import 'pc_file_list_bottom_status_bar.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../../transfer/controllers/upload_parts/upload_web_folder_drop_target_wrapper.dart';
import 'pc_file_drop_target.dart';
import '../../../transfer/views/upload/upload_drop_alert_view.dart';
import 'pc_file_search_filter_bar.dart';

//右侧区域：操作栏 + 文件列表 + 底部状态栏
class PcFileRightArea extends StatefulWidget {
  const PcFileRightArea({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;

  @override
  State<PcFileRightArea> createState() => _PcFileRightAreaState();
}

class _PcFileRightAreaState extends State<PcFileRightArea> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isSettings = widget.ctrl.rightPanel.value == 'index_settings';
      final allowExternalUploadDrop = widget.ctrl.allowExternalUploadDrop;
      if (isSettings) {
        if (!CurrentUserController.instance.isAdmin) {
          widget.ctrl.openFilePanel();
        } else {
          return _IndexSettingsView(ctrl: widget.ctrl);
        }
      }

      final customColors = Theme.of(context).extension<CustomColors>();
      Widget child = Container(
        color: customColors?.mainContentBgColor,
        child: Stack(
          children: [
            Column(
              children: [
                PcFileListOperationBar(ctrl: widget.ctrl),
                if (widget.ctrl.searchQuery.value.trim().isNotEmpty)
                  PcFileSearchFilterBar(ctrl: widget.ctrl),
                Expanded(child: PcFileList(ctrl: widget.ctrl)),
                PcFileBottomStatusBar(ctrl: widget.ctrl),
              ],
            ),
            if (_dragging &&
                allowExternalUploadDrop &&
                !kIsWeb &&
                widget.ctrl.searchQuery.value.trim().isEmpty)
              const UploadDropAlertView(),
          ],
        ),
      );

      if (!allowExternalUploadDrop) {
        return child;
      }

      if (kIsWeb) {
        return UploadWebFolderDropTargetWrapper(
          ctrl: widget.ctrl,
          child: child,
        );
      }

      return PcFileDropTargetWrapper(
        onDragDone: (files) async {
          setState(() {
            _dragging = false;
          });
          final supported = await widget.ctrl.ensureUploadSupported();
          if (!supported) return;
          final tc = Get.put(UploadController(), permanent: true);
          final target = widget.ctrl.currentPath.value ?? '/';
          tc.uploadDroppedFiles(files, target);
        },
        onDragEntered: () {
          setState(() {
            _dragging = true;
          });
        },
        onDragExited: () {
          setState(() {
            _dragging = false;
          });
        },
        child: child,
      );
    });
  }
}

class _IndexSettingsView extends StatefulWidget {
  const _IndexSettingsView({required this.ctrl});
  final PcFileExplorerController ctrl;

  @override
  State<_IndexSettingsView> createState() => _IndexSettingsViewState();
}

class _IndexSettingsViewState extends State<_IndexSettingsView> {
  late final TextEditingController _intervalCtrl;
  Worker? _intervalSyncWorker;

  @override
  void initState() {
    super.initState();
    _intervalCtrl = TextEditingController(
      text: widget.ctrl.indexIntervalHours.value.toString(),
    );
    _intervalSyncWorker = ever<int>(
      widget.ctrl.indexIntervalHours,
      (_) => _syncIntervalText(),
    );
  }

  @override
  void dispose() {
    _intervalSyncWorker?.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  void _syncIntervalText() {
    final desired = widget.ctrl.indexIntervalHours.value.toString();
    if (_intervalCtrl.text == desired) return;
    _intervalCtrl.value = _intervalCtrl.value.copyWith(
      text: desired,
      selection: TextSelection.collapsed(offset: desired.length),
      composing: TextRange.empty,
    );
  }

  int _safeIntervalHours() {
    final raw = _intervalCtrl.text.trim();
    final v = int.tryParse(raw);
    if (v == null) return 72;
    if (v < 1) return 1;
    if (v > 24 * 365) return 24 * 365;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();

    return Container(
      color: customColors?.mainContentBgColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                Text(
                  'file_index_settings'.tr,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              final loading = widget.ctrl.indexConfigLoading.value;
              final saving = widget.ctrl.indexConfigSaving.value;
              final enabled = widget.ctrl.indexEnabled.value;

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      CustomGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'file_index_settings_section_options'.tr,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              activeColor: theme.colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                              value: enabled,
                              onChanged: loading || saving
                                  ? null
                                  : (v) async {
                                      await widget.ctrl.saveIndexConfig(
                                        enabled: v,
                                        intervalHours: _safeIntervalHours(),
                                      );
                                    },
                              title: Text(
                                'file_index_enable_title'.tr,
                                style: theme.textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                'file_index_enable_subtitle'.tr,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _intervalCtrl,
                                    enabled: !loading && !saving,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText:
                                          'file_index_interval_label'.tr,
                                      hintText: 'file_index_interval_hint'.tr,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 40,
                                  child: ElevatedButton(
                                    onPressed: loading || saving
                                        ? null
                                        : () async {
                                            final ok =
                                                await widget.ctrl.saveIndexConfig(
                                              enabled:
                                                  widget.ctrl.indexEnabled.value,
                                              intervalHours:
                                                  _safeIntervalHours(),
                                            );
                                            if (!ok) return;
                                          },
                                    child: Text('save'.tr),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomGlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.restart_alt, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'file_index_section_maintenance'.tr,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonal(
                                onPressed: loading || saving
                                    ? null
                                    : () async {
                                        final confirmed =
                                            await DialogUtil.showConfirmDialog(
                                          title: 'need_confirm'.tr,
                                          content:
                                              'file_index_reset_confirm'.tr,
                                          confirmText: 'ok'.tr,
                                          cancelText: 'cancel'.tr,
                                        );
                                        if (confirmed != true) return;
                                        await widget.ctrl.resetIndex();
                                      },
                                child: Text('file_index_reset'.tr),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (loading)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
