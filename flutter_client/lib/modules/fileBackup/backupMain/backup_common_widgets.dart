part of 'file_backup_view.dart';

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final String? viewPath;
  final TextStyle? valueStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  final VoidCallback? onTap;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.viewPath,
    this.valueStyle,
    this.maxLines,
    this.overflow,
    this.selectable = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vStyle = valueStyle ?? theme.textTheme.bodyMedium;
    final canView =
        (viewPath ?? '').trim().isNotEmpty && value.trim().isNotEmpty;
    final viewStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final textWidget = selectable
        ? SelectableText(value, maxLines: maxLines, style: vStyle)
        : Text(value, maxLines: maxLines, overflow: overflow, style: vStyle);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
          Expanded(
            child: canView
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => _openFolderInFileBrowser(viewPath!),
                        child: Text('[${'perm_view'.tr}]', style: viewStyle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: textWidget),
                    ],
                  )
                : textWidget,
          ),
        ],
      ),
    );
  }
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
