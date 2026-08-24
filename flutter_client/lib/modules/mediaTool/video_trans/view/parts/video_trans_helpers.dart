part of '../video_trans_view.dart';

Color _statusColor(ThemeData theme, String status) {
  if (status == 'running') return theme.colorScheme.primary;
  if (status == 'error') return theme.colorScheme.error;
  return theme.colorScheme.onSurface.withValues(alpha: 0.65);
}

String _statusText(String status) {
  if (status == 'running') return 'media_tool_video_trans_status_running'.tr;
  if (status == 'stopped') return 'media_tool_video_trans_status_stopped'.tr;
  if (status == 'error') return 'media_tool_video_trans_status_error'.tr;
  return status;
}

String _nonVideoText(String v) {
  final s = v.trim().toLowerCase();
  if (s == 'copy') return 'media_tool_video_trans_non_video_copy'.tr;
  return 'skip'.tr;
}

String _lastErrorDisplayText(String raw) {
  final firstLine = raw.trim().split('\n').first.trim();
  if (firstLine.isEmpty) return '';
  final normalized = firstLine.toLowerCase();
  if (normalized.contains('ffmpeg was killed with signal sigkill')) {
    return 'media_tool_video_trans_status_stopped'.tr;
  }
  const mapped = {
    'source_not_found',
    'target_not_found',
    'target_not_dir',
    'target_no_access',
    'invalid_path_relation',
  };
  if (mapped.contains(firstLine)) return firstLine.tr;
  return firstLine;
}

String _formatText(String fmt) {
  final f = fmt.trim().toLowerCase();
  if (f.isEmpty) return '-';
  return f.toUpperCase();
}

void _openPathInFileBrowser(String targetPath) {
  final target = targetPath.trim();
  if (target.isEmpty) return;
  final openTarget = p.extension(target).isEmpty ? target : p.dirname(target);
  if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
    PcHomeController.instance.openFolderAt(openTarget);
    return;
  }
  AppRoutes.toFiles(initialPath: openTarget);
}

void _showTextDialog(BuildContext context, String title, String content) {
  showDialog(
    context: context,
    builder: (_) {
      return DialogUtil.createAlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(child: SelectableText(content)),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('ok'.tr)),
        ],
      );
    },
  );
}

Map<String, dynamic> _parseConfig(dynamic raw) {
  if (raw == null) return <String, dynamic>{};
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  if (raw is String) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
  }
  return <String, dynamic>{};
}
