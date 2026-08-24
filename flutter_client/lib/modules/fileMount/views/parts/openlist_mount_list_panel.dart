part of '../file_mount_view.dart';

class _OpenlistMountListPanel extends StatelessWidget {
  final OpenlistMountController ctrl;
  final bool showHeader;
  const _OpenlistMountListPanel({required this.ctrl, this.showHeader = true});

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
                    'file_mount_menu_openlist'.tr,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'openlist_mount_help_tooltip'.tr,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        DialogUtil.showInfoDialog(
                          title: 'file_mount_menu_openlist'.tr,
                          content: 'openlist_mount_help_tooltip'.tr,
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
                await ctrl.loadDrivers();
                await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _OpenlistMountDialog(ctrl: ctrl),
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
    final localMountDir = item['local_mount_dir']?.toString().trim() ?? '';
    final displayMountPath = localMountDir.isNotEmpty
        ? localMountDir
        : mountPath;
    final driver = item['driver']?.toString() ?? '';
    final lastError = item['last_error']?.toString() ?? '';
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
            _OpenlistKeyValueRow(
              label: 'openlist_mount_driver'.tr,
              value: OpenlistDriverI18n.driverName(driver),
            ),
            const SizedBox(height: 6),
            _OpenlistKeyValueRow(
              label: 'file_mount_mount_path'.tr,
              value: displayMountPath,
              viewPath: displayMountPath,
            ),
            if (lastError.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _OpenlistKeyValueRow(
                label: 'file_mount_last_error'.tr,
                value: lastError.split('\n').first,
                valueStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
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
                          await ctrl.loadDrivers();
                          await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) =>
                                _OpenlistMountDialog(ctrl: ctrl, initial: item),
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

class _OpenlistKeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final String? viewPath;
  final TextStyle? valueStyle;

  const _OpenlistKeyValueRow({
    required this.label,
    required this.value,
    this.viewPath,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value.isEmpty ? '-' : value;
    final canView = (viewPath ?? '').trim().isNotEmpty && text != '-';
    final viewStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

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
                    Expanded(
                      child: Text(
                        text,
                        style: valueStyle ?? theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                )
              : Text(text, style: valueStyle ?? theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
