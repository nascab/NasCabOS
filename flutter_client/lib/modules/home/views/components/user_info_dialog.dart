import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/app_window_title.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../utils/toast_util.dart';
import '../../../auth/beans/server_info_bean.dart';
import '../../../auth/service/server_storage_service.dart';
import '../../../music/play_service/controller/music_play_service_controller.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../../transfer/controllers/upload_controller.dart';
import '../../../transfer/models/transfer_task.dart';
import '../../../fileBackup/localBackup/local_backup_controller.dart';
import '../../../photoBackup/controller/photo_backup_controller.dart';

class UserInfoDialog extends StatefulWidget {
  const UserInfoDialog({super.key});

  @override
  State<UserInfoDialog> createState() => _UserInfoDialogState();
}

class _UserInfoDialogState extends State<UserInfoDialog> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      AppWindowTitle.applyDefault();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userCtrl = CurrentUserController.instance;
    final currentUser = userCtrl.current;

    // Find current server info
    final currentServerId = ApiController.instance.state.serverId;
    final currentBaseUrl = ApiController.instance.state.baseUrl;
    final currentUsername = (currentUser?.username ?? '').trim();
    final api = ApiController.instance;

    ServerInfoBean? currentServer;
    try {
      final servers = ServerStorageService.loadServers();
      // Try to find by serverId first
      if (currentServerId.isNotEmpty) {
        try {
          if (currentUsername.isNotEmpty) {
            currentServer = servers.firstWhere(
              (s) =>
                  s.serverId == currentServerId &&
                  (s.username ?? '').trim() == currentUsername,
            );
          } else {
            currentServer = servers.firstWhere(
              (s) => s.serverId == currentServerId,
            );
          }
        } catch (_) {}
      }

      // Fallback to url
      if (currentServer == null) {
        try {
          if (currentUsername.isNotEmpty) {
            currentServer = servers.firstWhere(
              (s) =>
                  s.serverUrl == currentBaseUrl &&
                  (s.username ?? '').trim() == currentUsername,
            );
          } else {
            currentServer = servers.firstWhere(
              (s) => s.serverUrl == currentBaseUrl,
            );
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading server info: $e');
      }
    }

    // Labels
    final serverNameLabel = 'server_name'.tr;
    final platformLabel = 'server_platform'.tr;
    final channelLabel = 'server_connect_channel'.tr;
    final serverIdLabel = 'server_id'.tr;
    final serverIpv4Value =
        kIsWeb ? '' : _resolveServerIpv4(currentServer, currentBaseUrl);

    final channelValue = api.connectChannelDisplayValue;
    final hasPairCode = (currentServer?.pairCode ?? '').trim().isNotEmpty;

    final sessionCh = (api.customHostname ?? '').trim();
    final storedCh = (currentServer?.customHostname ?? '').trim();
    final customDisp =
        sessionCh.isNotEmpty ? sessionCh : storedCh;
    final serverDisplayName = customDisp.isNotEmpty
        ? customDisp
        : ((currentServer?.serverName ?? '').trim().isNotEmpty
            ? currentServer!.serverName.trim()
            : (currentServer?.serverHostName ?? 'Unknown'));

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && ApiController.instance.isAuthenticated) {
          AppWindowTitle.applyForSession(ApiController.instance.customHostname);
        }
      },
      child: Dialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 330,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (currentUser?.username ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?.username ?? 'Unknown',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (currentUser?.phone != null &&
                            currentUser!.phone!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              currentUser.phone!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),

              // Server Info
              _buildInfoRow(
                context,
                serverNameLabel,
                serverDisplayName,
              ),
              const SizedBox(height: 16),
              _buildInfoRow(
                context,
                platformLabel,
                currentServer?.getPlatformFriendlyName() ?? 'Unknown',
                icon: _getPlatformIconPath(currentServer?.serverPlatform),
              ),
              const SizedBox(height: 16),
              _buildInfoRow(
                context,
                channelLabel,
                channelValue,
                trailing: (!kIsWeb || kDebugMode)
                    ? TextButton(
                        onPressed: () async {
                          try {
                            await _showDevConnectModePicker(
                              context,
                              hasPairCode: hasPairCode,
                            );
                          } catch (e) {
                            ToastUtil.show(
                              ApiController.formatP2pConnectError(e),
                            );
                          }
                        },
                        child: Text('dev_switch'.tr),
                      )
                    : null,
                wrapTooltip: true,
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 16),
                _buildInfoRow(
                  context,
                  'IP',
                  serverIpv4Value.isEmpty ? 'Unknown' : serverIpv4Value,
                ),
              ],
              const SizedBox(height: 16),
              _buildInfoRow(context, serverIdLabel, currentServerId),

              const SizedBox(height: 32),

              // Logout Button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: () {
                    _handleLogout();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: Text('home_status_logout'.tr),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    String? icon,
    Widget? trailing,
    bool wrapTooltip = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              if (icon != null) ...[
                Image.asset(icon, width: 20, height: 20),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: wrapTooltip
                    ? Tooltip(
                        message: value,
                        child: Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showDevConnectModePicker(
    BuildContext context, {
    required bool hasPairCode,
  }) async {
    final selected = await showDialog<DevConnectMode>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text('server_connect_channel'.tr),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(DevConnectMode.auto),
              child: Text('auto'.tr),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(DevConnectMode.direct),
              child: Text('dev_connect_mode_direct'.tr),
            ),
            if (hasPairCode) ...[
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(DevConnectMode.p2pDirect),
                child: Text('dev_connect_mode_p2p_direct'.tr),
              ),
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(DevConnectMode.p2pRelay),
                child: Text('dev_connect_mode_p2p_relay'.tr),
              ),
            ],
          ],
        );
      },
    );
    if (selected == null) return;
    await ApiController.instance.setDevConnectMode(selected);
    if (mounted) setState(() {});
  }

  /// 优先登录返回的 [ServerInfoBean.lanIpv4]，否则从当前 baseUrl / serverHost 取 IPv4。
  String _resolveServerIpv4(ServerInfoBean? server, String baseUrl) {
    final lan = (server?.lanIpv4 ?? '').trim();
    if (lan.isNotEmpty) return lan;
    final uri = Uri.tryParse(baseUrl.trim());
    final hostFromUrl = (uri?.host ?? '').trim();
    if (_isIpv4(hostFromUrl)) return hostFromUrl;
    final host = (server?.serverHost ?? '').trim();
    if (_isIpv4(host)) return host;
    return '';
  }

  bool _isIpv4(String host) {
    final s = host.trim();
    if (s.isEmpty) return false;
    if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(s)) return false;
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  String _getPlatformIconPath(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'darwin':
        return 'assets/home/server_mac.png';
      case 'win32':
        return 'assets/home/server_windows.png';
      case 'linux':
        return 'assets/home/server_linux.png';
      default:
        return 'assets/home/server_linux.png';
    }
  }

  void _handleLogout() {
    _handleLogoutAsync();
  }

  Future<void> _handleLogoutAsync() async {
    final uploadCtrl = Get.isRegistered<UploadController>()
        ? UploadController.instance
        : null;
    final downloadCtrl = Get.isRegistered<DownloadController>()
        ? Get.find<DownloadController>()
        : null;
    final photoBackupCtrl = Get.isRegistered<PhotoBackupController>()
        ? Get.find<PhotoBackupController>()
        : null;
    final localBackupCtrl = Get.isRegistered<LocalBackupController>()
        ? Get.find<LocalBackupController>()
        : null;

    final runningUploads = uploadCtrl == null
        ? const <TransferTask>[]
        : uploadCtrl.tasks
              .where(
                (t) =>
                    t.status == TransferStatus.pending ||
                    t.status == TransferStatus.uploading,
              )
              .toList();
    final runningDownloads = downloadCtrl == null
        ? const <TransferTask>[]
        : downloadCtrl.tasks
              .where((t) => t.status == TransferStatus.uploading)
              .toList();
    final photoBackupRunning = photoBackupCtrl != null &&
        photoBackupCtrl.tasks.any(
          (t) => photoBackupCtrl.runtimeOf(t.id).running.value,
        );
    final localBackupRunning = localBackupCtrl != null &&
        localBackupCtrl.profiles.any(
          (p) => localBackupCtrl.runtimeOf(p.id).busy.value,
        );

    if (runningUploads.isNotEmpty ||
        runningDownloads.isNotEmpty ||
        photoBackupRunning ||
        localBackupRunning) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('logout_transfer_running_title'.tr),
          content: Text('logout_transfer_running_content'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('confirm'.tr),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    if (uploadCtrl != null) {
      final active = uploadCtrl.tasks
          .where(
            (t) =>
                t.status == TransferStatus.pending ||
                t.status == TransferStatus.uploading,
          )
          .toList();
      for (final t in active) {
        try {
          uploadCtrl.deleteTask(t);
        } catch (_) {}
      }
    }

    if (downloadCtrl != null) {
      final running = downloadCtrl.tasks
          .where((t) => t.status == TransferStatus.uploading)
          .toList();
      for (final t in running) {
        try {
          await downloadCtrl.removeTask(t);
        } catch (_) {}
      }
    }

    photoBackupCtrl?.cancelAllRunning();
    localBackupCtrl?.stopAllRunningBackups();

    if (Get.isRegistered<MusicPlayServiceController>()) {
      final music = Get.find<MusicPlayServiceController>();
      unawaited(music.stop());
    }

    if (Get.isRegistered<LocalBackupController>()) {
      Get.find<LocalBackupController>().releaseRealtimeWatchers();
    }

    Get.find<CurrentUserController>().clear();
    ApiController.instance.clearAuthInfo();
    Get.back();

    if (kIsWeb) {
      AppRoutes.toLogin();
    } else {
      AppRoutes.toServerList();
    }
  }
}
