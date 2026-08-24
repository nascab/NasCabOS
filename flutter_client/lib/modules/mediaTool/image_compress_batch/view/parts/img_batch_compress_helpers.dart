part of '../img_batch_compress_view.dart';

Color _statusColor(ThemeData theme, String status) {
  if (status == 'running') return theme.colorScheme.primary;
  if (status == 'error') return theme.colorScheme.error;
  return theme.colorScheme.onSurface.withValues(alpha: 0.65);
}

String _statusText(String status) {
  if (status == 'running') return 'media_tool_img_batch_status_running'.tr;
  if (status == 'stopped') return 'media_tool_img_batch_status_stopped'.tr;
  if (status == 'error') return 'media_tool_img_batch_status_error'.tr;
  return status;
}

String _formatText(String fmt) {
  final f = fmt.trim().toLowerCase();
  if (f.isEmpty) return 'JPEG';
  return f.toUpperCase();
}

String _sizeText(dynamic v) {
  if (v == null) return 'media_tool_img_batch_keep_size'.tr;
  final n = int.tryParse(v.toString()) ?? 0;
  if (n <= 0) return 'media_tool_img_batch_keep_size'.tr;
  return '${'media_tool_out_size'.tr} $n';
}

String _nonImageText(String v) {
  final s = v.trim().toLowerCase();
  if (s == 'copy') return 'media_tool_img_batch_non_image_copy'.tr;
  return 'skip'.tr;
}

String _lastErrorDisplayText(String raw) {
  final firstLine = raw.trim().split('\n').first.trim();
  if (firstLine.isEmpty) return '';
  const mapped = {
    'source_not_found',
    'target_not_found',
    'target_not_dir',
    'target_no_access',
  };
  if (mapped.contains(firstLine)) return firstLine.tr;
  return firstLine;
}

void _openFolderInFileBrowser(String targetPath) {
  final target = targetPath.trim();
  if (target.isEmpty) return;
  if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
    PcHomeController.instance.openFolderAt(target);
    return;
  }
  AppRoutes.toFiles(initialPath: target);
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
