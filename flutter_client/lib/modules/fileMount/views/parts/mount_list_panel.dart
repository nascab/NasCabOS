part of '../file_mount_view.dart';

class _MountListPanel extends StatelessWidget {
  final FileMountController ctrl;
  final bool showHeader;
  const _MountListPanel({required this.ctrl, this.showHeader = true});

  void _showFullErrorDialog(BuildContext context, String fullError) {
    showDialog(
      context: context,
      builder: (_) {
        return DialogUtil.createAlertDialog(
          title: Text('file_mount_last_error'.tr),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(child: SelectableText(fullError)),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: Text('ok'.tr)),
          ],
        );
      },
    );
  }

  Color _statusColor(ThemeData theme, String status) {
    if (status == 'running') return theme.colorScheme.primary;
    if (status == 'error') return theme.colorScheme.error;
    return theme.colorScheme.onSurface.withValues(alpha: 0.65);
  }

  String _statusText(String status) {
    if (status == 'running') return 'file_mount_status_running'.tr;
    if (status == 'stopped') return 'file_mount_status_stopped'.tr;
    if (status == 'error') return 'file_mount_status_error'.tr;
    return status;
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'file_mount_menu_manage'.tr,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'file_mount_help_tooltip'.tr,
                    waitDuration: const Duration(milliseconds: 300),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        DialogUtil.showInfoDialog(
                          title: 'file_mount_menu_manage'.tr,
                          content: 'file_mount_help_tooltip'.tr,
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.help_outline, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CustomButton(
              text: 'refresh'.tr,
              onPressed: () => ctrl.refreshList(showLoading: true),
              isPrimary: false,
              icon: const Icon(Icons.refresh_outlined),
            ),
            const SizedBox(width: 8),
            CustomButton(
              text: 'create'.tr,
              onPressed: () async {
                final allowed = await ctrl.ensureWinfspReady();
                if (!allowed) return;
                await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _MountDialog(ctrl: ctrl),
                );
              },
              icon: const Icon(Icons.add_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    final status = item['status']?.toString() ?? 'stopped';
    final name = item['name']?.toString() ?? '';
    final mountPath = item['mount_path']?.toString() ?? '';
    final remote = item['remote']?.toString() ?? '';
    final lastErrorRaw = item['last_error']?.toString() ?? '';
    final lastErrorDisplay =
        item['last_error_display']?.toString().trim() ?? '';
    final lastError = lastErrorDisplay.isNotEmpty
        ? lastErrorDisplay
        : lastErrorRaw;
    final lastErrorFull = () {
      final d = lastErrorDisplay.trim();
      final r = lastErrorRaw.trim();
      if (r.isEmpty) return d;
      if (d.isNotEmpty && d != r) return '$d\n\n[$r]';
      return d.isNotEmpty ? d : r;
    }();
    final opLoading = ctrl.opLoadingById[id] == true;
    final canStop = status == 'running';
    final canStart = status != 'running';
    final canEdit = status != 'running' && !opLoading;

    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? '-' : name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _statusText(status),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _statusColor(theme, status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _KeyValueRow(
              label: 'file_mount_mount_path'.tr,
              value: mountPath,
              viewPath: mountPath,
            ),
            const SizedBox(height: 6),
            _KeyValueRow(label: 'file_mount_remote'.tr, value: remote),
            if (lastError.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              () {
                final full = lastErrorFull.trim();
                final firstLine = full.split('\n').first.trim();
                final shortLine = firstLine.isEmpty ? full : firstLine;
                return _KeyValueRow(
                  label: 'file_mount_last_error'.tr,
                  value: shortLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  selectable: false,
                  onTap: () => _showFullErrorDialog(context, full),
                  valueStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                );
              }(),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                CustomButton(
                  text: canStop ? 'file_mount_stop'.tr : 'file_mount_start'.tr,
                  onPressed: opLoading
                      ? null
                      : () {
                          if (canStop) {
                            ctrl.stop(id: id);
                          } else if (canStart) {
                            ctrl.start(id: id);
                          }
                        },
                  isDisabled: opLoading,
                  icon: opLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          canStop
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                        ),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'edit'.tr,
                  onPressed: canEdit
                      ? () async {
                          final allowed = await ctrl.ensureWinfspReady();
                          if (!allowed) return;
                          await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                _MountDialog(ctrl: ctrl, initial: item),
                          );
                        }
                      : null,
                  isPrimary: false,
                  isDisabled: !canEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'delete'.tr,
                  onPressed: id > 0 ? () => ctrl.remove(id: id) : null,
                  isPrimary: false,
                  isDisabled: id <= 0,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showHeader) {
      return Obx(() {
        final loading = ctrl.isLoading.value;
        final err = ctrl.errorText.value.trim();
        final list = ctrl.mounts;
        return CustomScrollView(
          slivers: [
            if (loading && list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (err.isNotEmpty && list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: CustomNoData(text: err),
              )
            else if (list.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: CustomNoData(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) => _buildItem(context, list[idx]),
                ),
              ),
          ],
        );
      });
    }

    return Obx(() {
      final loading = ctrl.isLoading.value;
      final err = ctrl.errorText.value.trim();
      final list = ctrl.mounts;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: 12, left: 12, right: 12),
            sliver: SliverToBoxAdapter(child: _buildHeader(context)),
          ),
          if (loading && list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (err.isNotEmpty && list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: CustomNoData(text: err),
            )
          else if (list.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: CustomNoData(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, idx) => _buildItem(context, list[idx]),
              ),
            ),
        ],
      );
    });
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
    final text = value.isEmpty ? '-' : value;
    final canView = (viewPath ?? '').trim().isNotEmpty && text != '-';
    final vStyle = valueStyle ?? theme.textTheme.bodySmall;
    final viewStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    Widget textNode;
    if (onTap != null || !selectable || maxLines != null) {
      textNode = InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: vStyle,
          maxLines: maxLines,
          overflow: overflow,
        ),
      );
    } else {
      textNode = SelectableText(text, style: vStyle);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: canView
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _openFolderInFileBrowser(viewPath!),
                      child: Text('[${'perm_view'.tr}]', style: viewStyle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: textNode),
                  ],
                )
              : textNode,
        ),
      ],
    );
  }
}
