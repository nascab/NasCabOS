import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/custom_colors.dart';
import '../../core/routes/app_routes.dart';
import '../base/components/custom_button.dart';
import '../base/components/custom_glass_card.dart';
import '../base/components/custom_no_data.dart';
import '../base/components/custom_switch.dart';
import '../home/views/pc_home_controller.dart';
import '../../utils/device_utils.dart';
import '../../utils/dialog_util.dart';
import '../../utils/toast_util.dart';
import '../files/views/folder_picker_dialog.dart';
import 'transmission_controller.dart';

void _openDownloadDirInFileBrowser(String targetPath) {
  final target = targetPath.trim();
  if (target.isEmpty) return;
  final openTarget = p.extension(target).isEmpty ? target : p.dirname(target);
  if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
    PcHomeController.instance.openFolderAt(openTarget);
    return;
  }
  AppRoutes.toFiles(initialPath: openTarget);
}

Future<void> _showTransmissionAddDialog(
  BuildContext context,
  TransmissionController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _AddTorrentDialog(controller: controller),
  );
}

class TransmissionView extends StatelessWidget {
  final bool appMode;

  const TransmissionView({super.key, this.appMode = false});

  @override
  Widget build(BuildContext context) {
    final useAppMode = appMode || DeviceUtils.isPhone(context);
    return GetBuilder<TransmissionController>(
      init: TransmissionController(),
      builder: (ctrl) {
        return Obx(() {
          if (ctrl.errorText.value.isNotEmpty) {
            return Scaffold(
              appBar: useAppMode
                  ? AppBar(
                      leading: const BackButton(),
                      title: Text('app_transmission'.tr),
                    )
                  : null,
              body: Center(child: Text(ctrl.errorText.value)),
            );
          }

          if (useAppMode) {
            return Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: Text('app_transmission'.tr),
                actions: [
                  IconButton(
                    tooltip: 'transmission_add_torrent'.tr,
                    icon: const Icon(Icons.add),
                    onPressed: () => _showTransmissionAddDialog(context, ctrl),
                  ),
                  IconButton(
                    tooltip: 'refresh'.tr,
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: () => ctrl.refreshAll(showLoading: false),
                  ),
                ],
              ),
              body: _TransmissionBody(controller: ctrl),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _mobileIndex(ctrl.currentTab.value),
                onTap: (i) => ctrl.currentTab.value = _tabForIndex(i),
                selectedItemColor: Theme.of(context).colorScheme.primary,
                unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.dashboard_outlined),
                    label: 'transmission_tab_overview'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.download_outlined),
                    label: 'transmission_tab_torrents'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.settings_outlined),
                    label: 'transmission_tab_settings'.tr,
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                _TransmissionSidebar(controller: ctrl),
                Expanded(child: _TransmissionBody(controller: ctrl)),
              ],
            ),
          );
        });
      },
    );
  }

  int _mobileIndex(String tab) {
    switch (tab) {
      case 'torrents':
        return 1;
      case 'settings':
        return 2;
      default:
        return 0;
    }
  }

  String _tabForIndex(int index) {
    switch (index) {
      case 1:
        return 'torrents';
      case 2:
        return 'settings';
      default:
        return 'overview';
    }
  }
}

class _TransmissionSidebar extends StatelessWidget {
  final TransmissionController controller;
  const _TransmissionSidebar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Obx(() {
      final tab = controller.currentTab.value;
      return Container(
        width: 180,
        decoration: BoxDecoration(
          color: customColors?.mainContentBgColor,
          border: Border(
            right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 40),
            _SidebarItem(
              icon: Icons.dashboard_outlined,
              label: 'transmission_tab_overview'.tr,
              selected: tab == 'overview',
              onTap: () => controller.currentTab.value = 'overview',
            ),
            _SidebarItem(
              icon: Icons.download_outlined,
              label: 'transmission_tab_torrents'.tr,
              selected: tab == 'torrents',
              onTap: () => controller.currentTab.value = 'torrents',
            ),
            _SidebarItem(
              icon: Icons.settings_outlined,
              label: 'transmission_tab_settings'.tr,
              selected: tab == 'settings',
              onTap: () => controller.currentTab.value = 'settings',
            ),
            const Spacer(),
            IconButton(
              tooltip: 'refresh'.tr,
              onPressed: () => controller.refreshAll(showLoading: false),
              icon: const Icon(Icons.refresh_outlined),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    });
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: selected ? theme.colorScheme.primary : null),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? theme.colorScheme.primary : null,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _TransmissionBody extends StatelessWidget {
  final TransmissionController controller;
  const _TransmissionBody({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !DeviceUtils.isPhone(context);
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Obx(() {
      late final Widget content;
      switch (controller.currentTab.value) {
        case 'torrents':
          content = _TorrentsTab(controller: controller);
          break;
        case 'settings':
          content = _SettingsTab(controller: controller);
          break;
        default:
          content = _OverviewTab(controller: controller);
      }
      if (!isDesktop) return content;
      return Container(
        color: customColors?.mainContentBgColor,
        child: Column(children: [Expanded(child: content)]),
      );
    });
  }
}

class _OverviewTab extends StatelessWidget {
  final TransmissionController controller;
  const _OverviewTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPhone = DeviceUtils.isPhone(context);
    return Obx(() {
      final running = controller.isRunning;
      final status = controller.status;
      final stats = controller.sessionStats;
      final statCards = <Widget>[
        _StatCard(
          fullWidth: isPhone,
          title: 'transmission_download_speed'.tr,
          value: controller.formatSpeed(
            (stats['downloadSpeed'] as num?)?.toInt(),
          ),
        ),
        _StatCard(
          fullWidth: isPhone,
          title: 'transmission_upload_speed'.tr,
          value: controller.formatSpeed(
            (stats['uploadSpeed'] as num?)?.toInt(),
          ),
        ),
        _StatCard(
          fullWidth: isPhone,
          title: 'transmission_active_torrents'.tr,
          value: '${stats['activeTorrentCount'] ?? 0}',
        ),
        _StatCard(
          fullWidth: isPhone,
          title: 'transmission_total_downloaded'.tr,
          value: controller.formatBytes(controller.overviewTotalDownloaded),
        ),
        _StatCard(
          fullWidth: isPhone,
          title: 'transmission_total_uploaded'.tr,
          value: controller.formatBytes(controller.overviewTotalUploaded),
        ),
      ];
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          CustomGlassCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running
                            ? 'transmission_service_running'.tr
                            : 'transmission_service_stopped'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${'transmission_configured_port'.tr}: ${status['configured_rpc_port'] ?? status['rpc_port'] ?? '-'}  '
                        '${'transmission_actual_port'.tr}: ${status['actual_rpc_port'] ?? '-'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (status['port_mismatch'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'transmission_restart_required'.tr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      if ((status['last_error']?.toString() ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${'error'.tr}: ${status['last_error']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (controller.serviceOperating.value)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                CustomSwitch(
                  value: running,
                  onChanged: controller.serviceOperating.value
                      ? null
                      : (v) => controller.toggleService(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (running)
            isPhone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < statCards.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        statCards[i],
                      ],
                    ],
                  )
                : Wrap(spacing: 12, runSpacing: 12, children: statCards)
          else
            CustomNoData(text: 'transmission_service_not_running'.tr),
        ],
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.title,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: fullWidth ? double.infinity : 180,
      child: CustomGlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _TorrentsTab extends StatelessWidget {
  final TransmissionController controller;
  const _TorrentsTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isPhone = DeviceUtils.isPhone(context);
    return Obx(() {
      if (!controller.isRunning) {
        return Center(child: Text('transmission_service_not_running'.tr));
      }
      final list = controller.displayTorrents;
      final theme = Theme.of(context);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'transmission_filter_all'.tr,
                          selected: controller.torrentFilter.value == 'all',
                          onTap: () => controller.torrentFilter.value = 'all',
                        ),
                        _FilterChip(
                          label: 'transmission_filter_downloading'.tr,
                          selected:
                              controller.torrentFilter.value == 'downloading',
                          onTap: () =>
                              controller.torrentFilter.value = 'downloading',
                        ),
                        _FilterChip(
                          label: 'transmission_filter_seeding'.tr,
                          selected: controller.torrentFilter.value == 'seeding',
                          onTap: () =>
                              controller.torrentFilter.value = 'seeding',
                        ),
                        _FilterChip(
                          label: 'transmission_filter_paused'.tr,
                          selected: controller.torrentFilter.value == 'paused',
                          onTap: () =>
                              controller.torrentFilter.value = 'paused',
                        ),
                        _FilterChip(
                          label: 'transmission_filter_error'.tr,
                          selected: controller.torrentFilter.value == 'error',
                          onTap: () => controller.torrentFilter.value = 'error',
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isPhone) ...[
                  IconButton(
                    tooltip: 'transmission_add_torrent'.tr,
                    onPressed: () =>
                        _showTransmissionAddDialog(context, controller),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'refresh'.tr,
                    onPressed: () =>
                        controller.refreshTorrents(showLoading: true),
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Text(
                  'sort'.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<String>(
                      tooltip: 'sort'.tr,
                      initialValue: controller.torrentSortKey.value,
                      onSelected: (value) =>
                          controller.torrentSortKey.value = value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sort_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                controller.torrentSortLabel(
                                  controller.torrentSortKey.value,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (context) {
                        return TransmissionController.torrentSortKeys
                            .map(
                              (key) => PopupMenuItem<String>(
                                value: key,
                                child: Text(controller.torrentSortLabel(key)),
                              ),
                            )
                            .toList();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? CustomNoData(text: 'transmission_no_torrents'.tr)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      return _TorrentCard(
                        controller: controller,
                        torrent: list[index],
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}

class _AddTorrentDialog extends StatefulWidget {
  final TransmissionController controller;
  const _AddTorrentDialog({required this.controller});

  @override
  State<_AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends State<_AddTorrentDialog> {
  int _mode = 0;
  final _urlCtrl = TextEditingController();
  final _downloadDirCtrl = TextEditingController();
  PlatformFile? _torrentFile;
  String? _serverTorrentPath;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.loadLastDownloadDir().then((path) {
      if (!mounted || path == null || path.isEmpty) return;
      setState(() => _downloadDirCtrl.text = path);
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _downloadDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: _downloadDirCtrl.text.trim(),
    );
    if (res == null || res.isEmpty) return;
    final picked = res.first.trim();
    if (picked.isEmpty) return;
    final ok = await widget.controller.validateAndSaveLastDownloadDir(picked);
    if (!mounted) return;
    if (!ok) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'upload_center_target_cannot_upload'.tr,
        buttonText: 'ok'.tr,
        onPressed: () => _pickFolder(),
      );
      return;
    }
    setState(() => _downloadDirCtrl.text = picked);
  }

  Future<void> _pickTorrentFileFromServer() async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: true,
      allowedExtensions: const ['torrent'],
      initialPath: _serverTorrentPath?.trim() ?? '',
    );
    if (res == null || res.isEmpty) return;
    final picked = res.first.trim();
    if (picked.isEmpty) return;
    setState(() {
      _serverTorrentPath = picked;
      _torrentFile = null;
    });
  }

  Future<void> _pickTorrentFileLocal() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['torrent'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _torrentFile = result.files.first;
      _serverTorrentPath = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final downloadDir = _downloadDirCtrl.text.trim();
    if (downloadDir.isEmpty) {
      ToastUtil.show('transmission_task_download_dir_required'.tr);
      return;
    }
    if (!await widget.controller.validateAndSaveLastDownloadDir(downloadDir)) {
      ToastUtil.show('upload_center_target_cannot_upload'.tr);
      return;
    }
    if (_mode == 0) {
      final url = _urlCtrl.text.trim();
      if (url.isEmpty) return;
      setState(() => _submitting = true);
      await widget.controller.addTorrent(url: url, downloadDir: downloadDir);
    } else {
      final serverPath = _serverTorrentPath?.trim() ?? '';
      if (_torrentFile == null && serverPath.isEmpty) return;
      setState(() => _submitting = true);
      if (serverPath.isNotEmpty) {
        await widget.controller.addTorrent(
          serverTorrentPath: serverPath,
          downloadDir: downloadDir,
        );
      } else {
        await widget.controller.addTorrent(
          torrentFile: _torrentFile,
          downloadDir: downloadDir,
        );
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('transmission_add_torrent'.tr),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text('transmission_add_by_magnet'.tr),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('transmission_add_by_file'.tr),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: 16),
              if (_mode == 0)
                TextField(
                  controller: _urlCtrl,
                  decoration: InputDecoration(
                    labelText: 'transmission_magnet_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                )
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickTorrentFileFromServer,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text('transmission_select_server_torrent_file'.tr),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickTorrentFileLocal,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text('transmission_upload_local_torrent_file'.tr),
                  ),
                ),
                if (_serverTorrentPath != null &&
                    _serverTorrentPath!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      p.basename(_serverTorrentPath!),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else if (_torrentFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _torrentFile!.name,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _downloadDirCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'transmission_task_download_dir'.tr,
                  hintText: 'transmission_task_download_dir_required'.tr,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open_outlined),
                    onPressed: _pickFolder,
                  ),
                ),
                onTap: _pickFolder,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('confirm'.tr),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _TorrentCard extends StatelessWidget {
  final TransmissionController controller;
  final Map<String, dynamic> torrent;

  const _TorrentCard({required this.controller, required this.torrent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = int.tryParse('${torrent['id']}') ?? 0;
    final name = torrent['name']?.toString() ?? '-';
    final percent = ((torrent['percentDone'] as num?) ?? 0).toDouble().clamp(
      0,
      1,
    );
    final loading = controller.opLoadingById[id] == true;
    final finished = controller.isTorrentFinished(torrent);
    final status = controller.statusLabelForTorrent(torrent);
    final downloadDir = torrent['downloadDir']?.toString() ?? '';
    final downloaded = controller.torrentDisplayDownloadedBytes(torrent);
    final totalSize = controller.torrentDisplayTotalSize(torrent);
    final uploaded = torrent['uploadedEver'] as num?;
    final ratio = torrent['uploadRatio'] as num?;
    final isLight = theme.brightness == Brightness.light;
    final completedAccent = isLight
        ? const Color(0xFF2E7D32)
        : theme.colorScheme.tertiary;
    final cardBase = theme.cardColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomGlassCard(
        border: finished
            ? Border.all(
                color: isLight
                    ? completedAccent.withValues(alpha: 0.28)
                    : completedAccent.withValues(alpha: 0.35),
              )
            : null,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (finished) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: completedAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: finished && !isLight
                        ? theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.78,
                            ),
                          )
                        : null,
                  ),
                ),
                if (finished) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isLight
                          ? const Color(0xFFE8F5E9)
                          : Color.lerp(cardBase, completedAccent, 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'completed'.tr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: completedAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (downloadDir.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () => _openDownloadDirInFileBrowser(downloadDir),
                    child: Text(
                      '[${'perm_view'.tr}]',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      downloadDir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: finished
                  ? 1.0
                  : (percent <= 0 ? null : percent.toDouble()),
              color: finished ? completedAccent : null,
              backgroundColor: finished
                  ? Color.lerp(cardBase, completedAccent, isLight ? 0.12 : 0.18)
                  : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '${controller.formatBytes(downloaded)} / ${controller.formatBytes(totalSize)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: finished && !isLight
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
                        : null,
                  ),
                ),
                Text(
                  '${'transmission_share_ratio'.tr}: ${controller.formatRatio(ratio)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${'transmission_torrent_uploaded'.tr}: ${controller.formatBytes(uploaded)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: finished ? completedAccent : null,
                    fontWeight: finished ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(percent * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: finished && !isLight
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '↓ ${controller.formatSpeed((torrent['rateDownload'] as num?)?.toInt())}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                Text(
                  '↑ ${controller.formatSpeed((torrent['rateUpload'] as num?)?.toInt())}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  if (!finished) ...[
                    TextButton(
                      onPressed: () => _showFilesDialog(context, id, name),
                      child: Text('transmission_select_files'.tr),
                    ),
                    TextButton(
                      onPressed: () =>
                          _changeDownloadDir(context, id, downloadDir),
                      child: Text('transmission_change_download_dir'.tr),
                    ),
                    if (controller.canShowTorrentStart(torrent))
                      TextButton(
                        onPressed: () => controller.startTorrent(id),
                        child: Text('transmission_torrent_start'.tr),
                      ),
                    if (controller.canShowTorrentPause(torrent))
                      TextButton(
                        onPressed: () => controller.stopTorrent(id),
                        child: Text('transmission_torrent_pause'.tr),
                      ),
                  ],
                  TextButton(
                    onPressed: () async {
                      final ok = await DialogUtil.showConfirmDialog(
                        title: 'confirm'.tr,
                        content: 'transmission_remove_confirm'.tr,
                      );
                      if (ok == true) {
                        await controller.removeTorrent(id);
                      }
                    },
                    child: Text('delete'.tr),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeDownloadDir(
    BuildContext context,
    int id,
    String currentDir,
  ) async {
    final res = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
      initialPath: currentDir,
    );
    if (res == null || res.isEmpty) return;
    final next = res.first.trim();
    if (next.isEmpty || next == currentDir) return;
    await controller.setTorrentDownloadDir(id, next);
  }

  Future<void> _showFilesDialog(
    BuildContext context,
    int id,
    String name,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _TorrentFilesDialog(
        controller: controller,
        torrentId: id,
        torrentName: name,
      ),
    );
  }
}

class _TorrentFilesDialog extends StatefulWidget {
  final TransmissionController controller;
  final int torrentId;
  final String torrentName;

  const _TorrentFilesDialog({
    required this.controller,
    required this.torrentId,
    required this.torrentName,
  });

  @override
  State<_TorrentFilesDialog> createState() => _TorrentFilesDialogState();
}

class _TorrentFilesDialogState extends State<_TorrentFilesDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _files = [];
  Map<int, bool> _wantedByIndex = {};
  Map<int, bool> _initialWantedByIndex = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.controller.loadTorrentFiles(widget.torrentId);
      if (!mounted) return;
      final wantedByIndex = <int, bool>{
        for (final file in files) _fileIndex(file): _isWanted(file),
      };
      setState(() {
        _files = files;
        _wantedByIndex = wantedByIndex;
        _initialWantedByIndex = Map<int, bool>.from(wantedByIndex);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isWanted(Map<String, dynamic> file) {
    final v = file['wanted'];
    if (v == false || v == 0) return false;
    return true;
  }

  int _fileIndex(Map<String, dynamic> file) {
    final v = file['index'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  bool get _dirty {
    if (_wantedByIndex.length != _initialWantedByIndex.length) return true;
    for (final entry in _wantedByIndex.entries) {
      if (_initialWantedByIndex[entry.key] != entry.value) return true;
    }
    return false;
  }

  void _setLocalWanted(int index, bool wanted) {
    setState(() => _wantedByIndex[index] = wanted);
  }

  void _setAllLocal(bool wanted) {
    if (_files.isEmpty) return;
    setState(() {
      for (final file in _files) {
        _wantedByIndex[_fileIndex(file)] = wanted;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      await widget.controller.saveTorrentFilesSelection(
        torrentId: widget.torrentId,
        wantedByIndex: Map<int, bool>.from(_wantedByIndex),
      );
      if (!mounted) return;
      ToastUtil.show('transmission_files_saved'.tr);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ToastUtil.show('operation_failed'.tr);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('transmission_torrent_files'.tr),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.torrentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (!_loading && _files.length > 1)
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => _setAllLocal(true),
                    child: Text('transmission_select_all_files'.tr),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _setAllLocal(false),
                    child: Text('transmission_deselect_all_files'.tr),
                  ),
                  if (_saving) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _files.isEmpty
                  ? Center(child: Text('transmission_no_files'.tr))
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        final fileName = file['name']?.toString() ?? '-';
                        final length = file['length'] as num?;
                        final fileIdx = _fileIndex(file);
                        final wanted = _wantedByIndex[fileIdx] ?? true;
                        return CheckboxListTile(
                          value: wanted,
                          onChanged: _saving
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  _setLocalWanted(fileIdx, v);
                                },
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(
                            fileName,
                            style: theme.textTheme.bodySmall,
                          ),
                          subtitle: Text(
                            widget.controller.formatBytes(length),
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        TextButton(
          onPressed: (_saving || !_dirty) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('save'.tr),
        ),
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  final TransmissionController controller;
  const _SettingsTab({required this.controller});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _rpcPortCtrl;
  late final TextEditingController _speedDownCtrl;
  late final TextEditingController _speedUpCtrl;
  late final TextEditingController _peerPortCtrl;
  late final TextEditingController _peerLimitGlobalCtrl;
  late final TextEditingController _peerLimitPerTorrentCtrl;
  late final TextEditingController _trackersCtrl;
  late final TextEditingController _trackerFetchTimeoutCtrl;
  bool _autoStart = false;
  bool _dht = true;
  bool _pex = true;
  bool _utp = true;
  bool _portForwarding = true;

  @override
  void initState() {
    super.initState();
    _rpcPortCtrl = TextEditingController();
    _speedDownCtrl = TextEditingController();
    _speedUpCtrl = TextEditingController();
    _peerPortCtrl = TextEditingController();
    _peerLimitGlobalCtrl = TextEditingController();
    _peerLimitPerTorrentCtrl = TextEditingController();
    _trackersCtrl = TextEditingController();
    _trackerFetchTimeoutCtrl = TextEditingController();
    _loadFromConfig();
  }

  void _loadFromConfig() {
    final cfg = widget.controller.config;
    _rpcPortCtrl.text = '${cfg['rpc_port'] ?? ''}';
    _speedDownCtrl.text = '${cfg['speed_limit_down'] ?? 0}';
    _speedUpCtrl.text = '${cfg['speed_limit_up'] ?? 0}';
    _peerPortCtrl.text = '${cfg['peer_port'] ?? ''}';
    _peerLimitGlobalCtrl.text = '${cfg['peer_limit_global'] ?? 200}';
    _peerLimitPerTorrentCtrl.text = '${cfg['peer_limit_per_torrent'] ?? 50}';
    _trackersCtrl.text = cfg['default_trackers']?.toString() ?? '';
    final timeoutMs =
        int.tryParse('${cfg['tracker_url_fetch_timeout_ms'] ?? 10000}') ??
        10000;
    _trackerFetchTimeoutCtrl.text = '${(timeoutMs / 1000).round()}';
    _autoStart = cfg['auto_start'] == true;
    _dht = cfg['dht_enabled'] == true;
    _pex = cfg['pex_enabled'] != false;
    _utp = cfg['utp_enabled'] != false;
    _portForwarding = cfg['port_forwarding'] != false;
  }

  @override
  void dispose() {
    _rpcPortCtrl.dispose();
    _speedDownCtrl.dispose();
    _speedUpCtrl.dispose();
    _peerPortCtrl.dispose();
    _peerLimitGlobalCtrl.dispose();
    _peerLimitPerTorrentCtrl.dispose();
    _trackersCtrl.dispose();
    _trackerFetchTimeoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.saveConfig({
      'rpc_port': int.tryParse(_rpcPortCtrl.text.trim()),
      'speed_limit_down': int.tryParse(_speedDownCtrl.text.trim()) ?? 0,
      'speed_limit_up': int.tryParse(_speedUpCtrl.text.trim()) ?? 0,
      'peer_port': int.tryParse(_peerPortCtrl.text.trim()),
      'peer_limit_global':
          int.tryParse(_peerLimitGlobalCtrl.text.trim()) ?? 200,
      'peer_limit_per_torrent':
          int.tryParse(_peerLimitPerTorrentCtrl.text.trim()) ?? 50,
      'default_trackers': _trackersCtrl.text.trim(),
      'tracker_url_fetch_timeout_ms':
          ((int.tryParse(_trackerFetchTimeoutCtrl.text.trim()) ?? 10).clamp(
            1,
            120,
          )) *
          1000,
      'auto_start': _autoStart,
      'dht_enabled': _dht,
      'pex_enabled': _pex,
      'utp_enabled': _utp,
      'port_forwarding': _portForwarding,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    return Container(
      color: customColors?.mainContentBgColor,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          CustomGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'transmission_tab_settings'.tr,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _rpcPortCtrl,
                  decoration: InputDecoration(
                    labelText: 'transmission_rpc_port'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _speedDownCtrl,
                        decoration: InputDecoration(
                          labelText: 'transmission_speed_limit_down'.tr,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _speedUpCtrl,
                        decoration: InputDecoration(
                          labelText: 'transmission_speed_limit_up'.tr,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _peerPortCtrl,
                  decoration: InputDecoration(
                    labelText: 'transmission_peer_port'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _peerLimitGlobalCtrl,
                        decoration: InputDecoration(
                          labelText: 'transmission_peer_limit_global'.tr,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _peerLimitPerTorrentCtrl,
                        decoration: InputDecoration(
                          labelText: 'transmission_peer_limit_per_torrent'.tr,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _trackersCtrl,
                  decoration: InputDecoration(
                    labelText: 'transmission_default_trackers'.tr,
                    hintText: 'transmission_default_trackers_hint'.tr,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  keyboardType: TextInputType.multiline,
                  minLines: 3,
                  maxLines: 8,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _trackerFetchTimeoutCtrl,
                  decoration: InputDecoration(
                    labelText: 'transmission_tracker_fetch_timeout'.tr,
                    hintText: 'transmission_tracker_fetch_timeout_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _SettingsSwitchRow(
                  label: 'transmission_auto_start'.tr,
                  value: _autoStart,
                  onChanged: (v) => setState(() => _autoStart = v),
                ),
                _SettingsSwitchRow(
                  label: 'transmission_dht_enabled'.tr,
                  value: _dht,
                  onChanged: (v) => setState(() => _dht = v),
                ),
                _SettingsSwitchRow(
                  label: 'transmission_pex_enabled'.tr,
                  value: _pex,
                  onChanged: (v) => setState(() => _pex = v),
                ),
                _SettingsSwitchRow(
                  label: 'transmission_utp_enabled'.tr,
                  value: _utp,
                  onChanged: (v) => setState(() => _utp = v),
                ),
                _SettingsSwitchRow(
                  label: 'transmission_port_forwarding'.tr,
                  value: _portForwarding,
                  onChanged: (v) => setState(() => _portForwarding = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CustomButton(
                      text: 'save'.tr,
                      onPressed: widget.controller.savingConfig.value
                          ? null
                          : _save,
                    ),
                    const SizedBox(width: 12),
                    CustomButton(
                      text: 'transmission_restart_service'.tr,
                      onPressed: widget.controller.serviceOperating.value
                          ? null
                          : () => widget.controller.restartService(),
                      isPrimary: false,
                      icon: const Icon(Icons.restart_alt_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          CustomSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
