part of '../media_arrange_view.dart';

Color _statusColor(ThemeData theme, String status) {
  if (status == 'running') return theme.colorScheme.primary;
  if (status == 'error') return theme.colorScheme.error;
  return theme.colorScheme.onSurface.withValues(alpha: 0.65);
}

String _statusText(String status) {
  if (status == 'running') return 'media_tool_arrange_status_running'.tr;
  if (status == 'stopped') return 'media_tool_arrange_status_stopped'.tr;
  if (status == 'error') return 'media_tool_arrange_status_error'.tr;
  if (status == 'finished') return 'completed'.tr;
  return status;
}

String _arrangeTypeText(String type) {
  if (type == 'year') return 'media_tool_arrange_type_year'.tr;
  if (type == 'month') return 'media_tool_arrange_type_month'.tr;
  if (type == 'day') return 'media_tool_arrange_type_day'.tr;
  return type;
}

String _lastErrorDisplayText(String raw) {
  final firstLine = raw.trim().split('\n').first.trim();
  if (firstLine.isEmpty) return '';
  const mapped = {
    'source_not_found',
    'target_not_found',
    'target_not_dir',
    'target_no_access',
    'invalid_path_relation',
    'mediaTool.SOURCE_NOT_FOUND',
    'mediaTool.TARGET_NO_WRITE_PERMISSION',
    'mediaTool.TARGET_NOT_EMPTY',
    'mediaTool.TARGET_ACCESS_ERROR',
    'mediaTool.PATH_CONFLICT',
  };
  if (mapped.contains(firstLine)) return firstLine.tr;
  return firstLine;
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
