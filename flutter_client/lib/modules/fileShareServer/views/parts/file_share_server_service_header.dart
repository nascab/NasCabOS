part of '../file_share_server_view.dart';

class _ServiceHeader extends StatelessWidget {
  final String serverType;
  final FileShareServerController ctrl;
  const _ServiceHeader({required this.serverType, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final status = ctrl.getStatus(serverType);
      final enabled = status == 'running';
      final ports = ctrl.getDisplayPorts(serverType);
      final httpPort = ports['http_port']?.toString() ?? '';
      final httpsPort = ports['https_port']?.toString() ?? '';
      final loading = ctrl.opLoadingByType[serverType] == true;
      final plugin = MountPluginStatusService.ensure();
      final canStart = plugin.canUseFileServer;

      final statusText = status == 'running'
          ? 'file_share_server_status_running'.tr
          : status == 'stopped'
          ? 'file_share_server_status_stopped'.tr
          : status;

      return CustomGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(statusText, style: theme.textTheme.titleMedium),
                        const SizedBox(width: 10),
                        Text(
                          '${'file_share_server_http'.tr}: ${httpPort.isEmpty ? '-' : httpPort}  '
                          '${'file_share_server_https'.tr}: ${httpsPort.isEmpty ? '-' : httpsPort}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      enabled
                          ? 'file_share_server_enabled'.tr
                          : 'file_share_server_disabled'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
              ],
              CustomSwitch(
                value: enabled,
                onChanged: loading || (!enabled && !canStart)
                    ? null
                    : (v) async {
                        if (v) {
                          await ctrl.start(serverType);
                        } else {
                          await ctrl.stop(serverType);
                        }
                      },
              ),
            ],
          ),
        ),
      );
    });
  }
}
