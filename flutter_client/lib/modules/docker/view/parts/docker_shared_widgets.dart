part of '../docker_manager_view.dart';

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $value', style: theme.textTheme.bodySmall),
    );
  }
}

class _ContainerInfoTag extends StatelessWidget {
  final String text;

  const _ContainerInfoTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomTag(
      border: Border.all(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        width: 1,
      ),
      text: text,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      textColor: theme.colorScheme.onSurface,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: EdgeInsets.zero,
      textStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  final String label;
  final String value;

  const _KvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = status.trim().toLowerCase();
    final running = normalized == 'running' || normalized == 'success';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: running
            ? Colors.green.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _translateTaskStatus(normalized),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: running ? Colors.green.shade700 : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

String _translateTaskStatus(String status) {
  switch (status) {
    case 'queued':
      return 'docker_task_status_queued'.tr;
    case 'running':
      return 'docker_task_status_running'.tr;
    case 'success':
      return 'docker_task_status_success'.tr;
    case 'failed':
      return 'docker_task_status_failed'.tr;
    case 'cancelled':
      return 'docker_task_status_cancelled'.tr;
    default:
      return status.isEmpty ? '--' : status;
  }
}

String _translateTaskType(String type) {
  final normalized = type.trim().toLowerCase();
  switch (normalized) {
    case 'start_docker':
      return 'docker_task_type_start_docker'.tr;
    case 'stop_docker':
      return 'docker_task_type_stop_docker'.tr;
    case 'pull_image':
      return 'docker_task_type_pull_image'.tr;
    case 'import_image':
      return 'docker_task_type_import_image'.tr;
    case 'container_logs':
      return 'docker_task_type_container_logs'.tr;
    default:
      if (normalized.isEmpty) return '--';
      return normalized.replaceAll('_', ' ');
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;

  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTaskLogLine(Map<String, dynamic> item) {
  final line = item['text']?.toString() ?? '';
  final source = item['source']?.toString() ?? '';
  final ts = item['ts']?.toString() ?? '';
  return '[$source] $ts  $line';
}

Future<void> _copyText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  ToastUtil.show('docker_logs_copied'.tr);
}
