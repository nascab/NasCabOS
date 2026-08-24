part of '../backupMain/file_backup_view.dart';

class _ServerBackupListPanel extends StatelessWidget {
  final FileBackupController ctrl;
  final bool showHeader;
  const _ServerBackupListPanel({required this.ctrl, this.showHeader = true});

  void _showBackupRecordsDialog(BuildContext context, int taskId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BackupRecordsDialog(taskId: taskId, ctrl: ctrl),
    );
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

  Color _statusColor(ThemeData theme, String status) {
    if (status == 'running') return theme.colorScheme.primary;
    if (status == 'error') return theme.colorScheme.error;
    return theme.colorScheme.onSurface.withValues(alpha: 0.65);
  }

  String _statusText(String status) {
    if (status == 'running') return 'file_backup_status_running'.tr;
    if (status == 'stopped') return 'file_backup_status_stopped'.tr;
    if (status == 'disabled') return 'file_backup_status_disabled'.tr;
    if (status == 'error') return 'file_backup_status_error'.tr;
    return status;
  }

  String _typeText(String type) {
    if (type == 'sync') return 'file_backup_type_sync'.tr;
    return 'file_backup_type_copy'.tr;
  }

  String _friendlyLastError(String lastError) {
    final code = lastError.trim().toLowerCase();
    if (code == 'target_not_found') {
      return 'target_not_found'.tr;
    }
    if (code == 'source_not_found') {
      return 'source_not_found'.tr;
    }
    return lastError.trim();
  }

  String _formatLocalTime(dynamic v) {
    DateTime? dt;
    if (v is DateTime) {
      dt = v;
    } else if (v is int) {
      final isMs = v > 10000000000;
      dt = DateTime.fromMillisecondsSinceEpoch(isMs ? v : v * 1000);
    } else if (v is String) {
      final s = v.trim();
      final n = int.tryParse(s);
      if (n != null) {
        final isMs = n > 10000000000;
        dt = DateTime.fromMillisecondsSinceEpoch(isMs ? n : n * 1000);
      } else {
        dt = DateTime.tryParse(s);
      }
    }
    if (dt == null) return '-';
    final local = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _lastBackupStatusText({
    required String lastError,
    required dynamic lastSuccessTime,
  }) {
    if (lastError.trim().isNotEmpty) {
      return 'file_backup_last_backup_status_failed'.tr;
    }
    if (lastSuccessTime == null) {
      return 'file_backup_last_backup_status_unknown'.tr;
    }
    final s = lastSuccessTime.toString().trim();
    if (s.isEmpty) return 'file_backup_last_backup_status_unknown'.tr;
    return 'file_backup_last_backup_status_success'.tr;
  }

  List<String> _toStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e?.toString() ?? '')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final compact = DeviceUtils.isPhone(context);
    final edgePadding = compact ? EdgeInsets.zero : const EdgeInsets.all(12);

    Widget buildHeader() {
      return CustomGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'file_backup_menu_disk'.tr,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'file_backup_help_tooltip'.tr,
                      waitDuration: const Duration(milliseconds: 300),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          DialogUtil.showInfoDialog(
                            title: 'file_backup_menu_disk'.tr,
                            content: 'file_backup_help_tooltip'.tr,
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
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => _ServerBackupDialog(ctrl: ctrl),
                  );
                },
                icon: const Icon(Icons.add_outlined),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: customColors?.mainContentBgColor,
      child: CustomScrollView(
        slivers: [
          if (showHeader)
            SliverPadding(
              padding: edgePadding.copyWith(bottom: 6),
              sliver: SliverToBoxAdapter(child: buildHeader()),
            ),
          Obx(() {
            final loading = ctrl.isLoading.value;
            final err = ctrl.errorText.value.trim();
            final list = ctrl.tasks;
            if (loading && list.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (err.isNotEmpty && list.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: CustomNoData(text: err),
              );
            }
            if (list.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: CustomNoData(),
              );
            }

            final listPadding = showHeader
                ? edgePadding.copyWith(top: 0)
                : edgePadding;

            return SliverPadding(
              padding: listPadding,
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, idx) {
                  final item = list[idx];
                  final id = int.tryParse(item['id']?.toString() ?? '') ?? 0;
                  final status =
                      item['status']?.toString().trim().toLowerCase() ??
                      'stopped';
                  final type =
                      item['type']?.toString().trim().toLowerCase() ?? 'copy';
                  final sources = _toStringList(item['source_path']);
                  final targetPath = item['target_path']?.toString() ?? '';
                  final freq =
                      int.tryParse(item['frenquence']?.toString() ?? '') ?? 0;
                  final excludes = _toStringList(item['exclude_list']);
                  final progress = item['progress']?.toString() ?? '';
                  final lastSuccessTime = item['last_success_time'];
                  final lastError = item['last_error']?.toString() ?? '';

                  final opLoading = ctrl.opLoadingById[id] == true;
                  final canStop = status == 'running';
                  final canStart = status != 'running';
                  final canEdit = status != 'running' && !opLoading;

                  final sourcesText = sources.isEmpty
                      ? 'file_backup_source_empty'.tr
                      : sources.length == 1
                      ? sources.first
                      : '${sources.first} (+${sources.length - 1})';
                  final excludeText = excludes.isEmpty
                      ? '-'
                      : excludes.length == 1
                      ? excludes.first
                      : '${excludes.first} (+${excludes.length - 1})';

                  final lastBackupTimeText = lastSuccessTime == null
                      ? '-'
                      : _formatLocalTime(lastSuccessTime);

                  String? errorShortLine;
                  String? errorFullText;
                  if (lastError.trim().isNotEmpty) {
                    final full = lastError.trim();
                    final firstLine = _friendlyLastError(
                      full.split('\n').first.trim(),
                    );
                    errorShortLine = firstLine.isEmpty ? full : firstLine;
                    errorFullText = _friendlyLastError(full);
                  }

                  return Padding(
                           padding: compact
                        ? const EdgeInsets.all(12)
                        : const EdgeInsets.only(bottom: 8),
                    child: _ServerBackupListItemCard(
                    theme: theme,
                    id: id,
                    typeText: _typeText(type),
                    statusText: _statusText(status),
                    statusColor: _statusColor(theme, status),
                    sourcesLabel: 'file_backup_source_paths'.tr,
                    sourcesText: sourcesText,
                    sourcesViewPath: sources.isEmpty ? null : sources.first,
                    sourcesSelectable: sources.length <= 1,
                    onSourcesTap: sources.length > 1
                        ? () => _showTextDialog(
                            context,
                            'file_backup_source_paths'.tr,
                            sources.join('\n'),
                          )
                        : null,
                    targetLabel: 'file_backup_target_path'.tr,
                    targetPath: targetPath,
                    targetViewPath: targetPath.trim().isEmpty
                        ? null
                        : targetPath.trim(),
                    freqLabel: 'file_backup_frequency_hours'.tr,
                    freqText: freq > 0 ? freq.toString() : '-',
                    excludeLabel: 'exclude_list'.tr,
                    excludeText: excludeText,
                    excludeSelectable: excludes.length <= 1,
                    onExcludeTap: excludes.length > 1
                        ? () => _showTextDialog(
                            context,
                            'exclude_list'.tr,
                            excludes.join('\n'),
                          )
                        : null,
                    lastBackupTimeLabel: 'file_backup_last_backup_time'.tr,
                    lastBackupTimeText: lastBackupTimeText,
                    lastBackupStatusLabel: 'file_backup_last_backup_status'.tr,
                    lastBackupStatusText: _lastBackupStatusText(
                      lastError: lastError,
                      lastSuccessTime: lastSuccessTime,
                    ),
                    showProgress: status == 'running',
                    progressLabel: 'file_backup_progress'.tr,
                    progressText: progress.isEmpty ? '-' : progress,
                    errorLabel: 'file_backup_last_error'.tr,
                    errorShortText: errorShortLine,
                    onErrorTap: errorFullText == null
                        ? null
                        : () => _showTextDialog(
                            context,
                            'file_backup_last_error'.tr,
                            errorFullText!,
                          ),
                    errorTextStyle: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    canStop: canStop,
                    canStart: canStart,
                    opLoading: opLoading,
                    onToggleStartStop: () {
                      if (canStop) {
                        ctrl.stop(id: id);
                      } else if (canStart) {
                        ctrl.start(id: id);
                      }
                    },
                    canEdit: canEdit,
                    onEdit: () async {
                      await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            _ServerBackupDialog(ctrl: ctrl, initial: item),
                      );
                    },
                    canDelete: id > 0,
                    onDelete: id > 0 ? () => ctrl.remove(id: id) : null,
                    onBackupRecords: id > 0
                        ? () => _showBackupRecordsDialog(context, id)
                        : null,
                  ),
                );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ServerBackupListItemCard extends StatelessWidget {
  final ThemeData theme;
  final int id;
  final String typeText;
  final String statusText;
  final Color statusColor;
  final String sourcesLabel;
  final String sourcesText;
  final String? sourcesViewPath;
  final bool sourcesSelectable;
  final VoidCallback? onSourcesTap;
  final String targetLabel;
  final String targetPath;
  final String? targetViewPath;
  final String freqLabel;
  final String freqText;
  final String excludeLabel;
  final String excludeText;
  final bool excludeSelectable;
  final VoidCallback? onExcludeTap;
  final String lastBackupTimeLabel;
  final String lastBackupTimeText;
  final String lastBackupStatusLabel;
  final String lastBackupStatusText;
  final bool showProgress;
  final String progressLabel;
  final String progressText;
  final String errorLabel;
  final String? errorShortText;
  final VoidCallback? onErrorTap;
  final TextStyle? errorTextStyle;
  final bool canStop;
  final bool canStart;
  final bool opLoading;
  final VoidCallback onToggleStartStop;
  final bool canEdit;
  final Future<void> Function() onEdit;
  final bool canDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onBackupRecords;

  const _ServerBackupListItemCard({
    required this.theme,
    required this.id,
    required this.typeText,
    required this.statusText,
    required this.statusColor,
    required this.sourcesLabel,
    required this.sourcesText,
    required this.sourcesViewPath,
    required this.sourcesSelectable,
    required this.onSourcesTap,
    required this.targetLabel,
    required this.targetPath,
    required this.targetViewPath,
    required this.freqLabel,
    required this.freqText,
    required this.excludeLabel,
    required this.excludeText,
    required this.excludeSelectable,
    required this.onExcludeTap,
    required this.lastBackupTimeLabel,
    required this.lastBackupTimeText,
    required this.lastBackupStatusLabel,
    required this.lastBackupStatusText,
    required this.showProgress,
    required this.progressLabel,
    required this.progressText,
    required this.errorLabel,
    required this.errorShortText,
    required this.onErrorTap,
    required this.errorTextStyle,
    required this.canStop,
    required this.canStart,
    required this.opLoading,
    required this.onToggleStartStop,
    required this.canEdit,
    required this.onEdit,
    required this.canDelete,
    required this.onDelete,
    required this.onBackupRecords,
  });

  @override
  Widget build(BuildContext context) {
    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#$id · $typeText',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                statusText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _KeyValueRow(
            label: sourcesLabel,
            value: sourcesText,
            viewPath: sourcesViewPath,
            selectable: sourcesSelectable,
            onTap: onSourcesTap,
          ),
          const SizedBox(height: 6),
          _KeyValueRow(
            label: targetLabel,
            value: targetPath,
            viewPath: targetViewPath,
          ),
          const SizedBox(height: 6),
          _KeyValueRow(label: freqLabel, value: freqText),
          const SizedBox(height: 6),
          _KeyValueRow(
            label: excludeLabel,
            value: excludeText,
            selectable: excludeSelectable,
            onTap: onExcludeTap,
          ),
          const SizedBox(height: 6),
          _KeyValueRow(label: lastBackupTimeLabel, value: lastBackupTimeText),
          const SizedBox(height: 6),
          _KeyValueRow(
            label: lastBackupStatusLabel,
            value: lastBackupStatusText,
          ),
          if (showProgress) ...[
            const SizedBox(height: 6),
            _KeyValueRow(label: progressLabel, value: progressText),
          ],
          if ((errorShortText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _KeyValueRow(
              label: errorLabel,
              value: errorShortText!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              selectable: false,
              onTap: onErrorTap,
              valueStyle: errorTextStyle,
            ),
          ],
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                CustomButton(
                  text: canStop
                      ? 'file_backup_stop'.tr
                      : 'file_backup_start'.tr,
                  onPressed: opLoading ? null : onToggleStartStop,
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
                  onPressed: canEdit ? () async => await onEdit() : null,
                  isPrimary: false,
                  isDisabled: !canEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'delete'.tr,
                  onPressed: canDelete ? onDelete : null,
                  isPrimary: false,
                  isDisabled: !canDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
                if (onBackupRecords != null) ...[
                  const SizedBox(width: 8),
                  CustomButton(
                    text: 'file_backup_run_records'.tr,
                    onPressed: onBackupRecords,
                    isPrimary: false,
                    icon: const Icon(Icons.history_outlined),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _BackupRecordsDialog extends StatefulWidget {
  final int taskId;
  final FileBackupController ctrl;

  const _BackupRecordsDialog({required this.taskId, required this.ctrl});

  @override
  State<_BackupRecordsDialog> createState() => _BackupRecordsDialogState();
}

class _BackupRecordsDialogState extends State<_BackupRecordsDialog> {
  static const TextHeightBehavior _tightTextHeight = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.ctrl.fetchBackupRecords(taskId: widget.taskId);
  }

  String _formatLocalTime(dynamic v) {
    DateTime? dt;
    if (v is DateTime) {
      dt = v;
    } else if (v is int) {
      final isMs = v > 10000000000;
      dt = DateTime.fromMillisecondsSinceEpoch(isMs ? v : v * 1000);
    } else if (v is String) {
      final s = v.trim();
      final n = int.tryParse(s);
      if (n != null) {
        final isMs = n > 10000000000;
        dt = DateTime.fromMillisecondsSinceEpoch(isMs ? n : n * 1000);
      } else {
        dt = DateTime.tryParse(s);
      }
    }
    if (dt == null) return 'file_backup_run_records_na'.tr;
    final local = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _formatBytes(dynamic v) {
    final n = int.tryParse(v?.toString() ?? '') ?? 0;
    if (n < 0) return 'file_backup_run_records_na'.tr;
    if (n < 1024) {
      return 'file_backup_run_record_bytes_value'.trParams({'n': n.toString()});
    }
    const units = ['KB', 'MB', 'GB', 'TB'];
    double x = n / 1024;
    var i = 0;
    while (x >= 1024 && i < units.length - 1) {
      x /= 1024;
      i++;
    }
    final s = x >= 100
        ? x.toStringAsFixed(0)
        : x >= 10
        ? x.toStringAsFixed(1)
        : x.toStringAsFixed(2);
    return 'file_backup_run_record_bytes_shorthand'.trParams({
      'v': s,
      'u': units[i],
    });
  }

  String _formatDurationMs(dynamic v) {
    if (v == null) return 'file_backup_run_records_na'.tr;
    final ms = int.tryParse(v.toString().trim());
    if (ms == null || ms < 0) return 'file_backup_run_records_na'.tr;
    final totalSeconds = ms == 0
        ? 0
        : ms < 1000
            ? 1
            : ms ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  void _showErrorFilesDialog(
    BuildContext context,
    List<Map<String, String>> errors,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.12);
    final labelSmall = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.65),
      height: 1.1,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: cs.surface,
          child: SizedBox(
            width: 520,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'file_backup_run_record_error_files_dialog_title'
                              .tr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'cancel'.tr,
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: errors.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (_, i) {
                      final e = errors[i];
                      final p = e['path'] ?? '';
                      final r = e['error'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'file_backup_run_record_error_path'.tr,
                              style: labelSmall,
                            ),
                            Text(
                              p.trim().isEmpty
                                  ? 'file_backup_run_records_na'.tr
                                  : p,
                              style: valueStyle,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'file_backup_run_record_error_reason'.tr,
                              style: labelSmall,
                            ),
                            Text(
                              r.trim().isEmpty
                                  ? 'file_backup_run_records_na'.tr
                                  : r,
                              style: valueStyle?.copyWith(color: cs.error),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('ok'.tr),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _errorFilesSummaryRow(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    List<Map<String, String>> errors,
  ) {
    if (errors.isEmpty) {
      return _kv(
        theme,
        cs,
        'file_backup_run_record_error_files'.tr,
        'file_backup_run_records_na'.tr,
      );
    }
    final first = errors.first;
    final path = (first['path'] ?? '').trim();
    final err = (first['error'] ?? '').trim();
    final preview = path.isEmpty && err.isEmpty
        ? 'file_backup_run_records_na'.tr
        : path.isEmpty
        ? err
        : err.isEmpty
        ? path
        : '$path: $err';

    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.7),
      height: 1.12,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.12);
    final extra = errors.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'file_backup_run_record_error_files'.tr,
              style: labelStyle,
              textHeightBehavior: _tightTextHeight,
            ),
          ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                onTap: () => _showErrorFilesDialog(context, errors),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                          textHeightBehavior: _tightTextHeight,
                        ),
                      ),
                      if (extra > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          'file_backup_run_record_error_more'
                              .trParams({'n': '$extra'}),
                          style: valueStyle?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          textHeightBehavior: _tightTextHeight,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _recordStatusText(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'running') return 'file_backup_record_status_running'.tr;
    if (s == 'success') return 'file_backup_record_status_success'.tr;
    if (s == 'failed') return 'file_backup_record_status_failed'.tr;
    if (s == 'stopped') return 'file_backup_record_status_stopped'.tr;
    return raw.trim().isEmpty ? 'file_backup_run_records_na'.tr : raw.trim();
  }

  Widget _kv(
    ThemeData theme,
    ColorScheme cs,
    String label,
    String value, {
    int maxLines = 4,
  }) {
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.7),
      height: 1.12,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: labelStyle,
              textHeightBehavior: _tightTextHeight,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textHeightBehavior: _tightTextHeight,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'file_backup_run_records_title'.trParams({
                        'id': '${widget.taskId}',
                      }),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Get.back<void>(),
                    icon: const Icon(Icons.close),
                    tooltip: 'cancel'.tr,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError || snap.data == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'file_backup_run_records_load_failed'.tr,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: cs.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final data = snap.data!;
                  final maxKept = int.tryParse(
                        data['max_kept_per_task']?.toString() ?? '',
                      ) ??
                      300;
                  final items = data['items'];
                  final list = (items is List ? items : const [])
                      .whereType<Map>()
                      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                      .toList();

                  if (list.isEmpty) {
                    return CustomNoData(
                      text: 'file_backup_run_records_empty'.tr,
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Text(
                          'file_backup_run_record_max_kept_note'.trParams({
                            'n': '$maxKept',
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final row = list[i];
                            final errList = row['error_file_list'];
                            final errors = errList is List
                                ? errList
                                    .whereType<Map>()
                                    .map(
                                      (m) => m.map(
                                        (k, v) => MapEntry(
                                          k.toString(),
                                          v?.toString() ?? '',
                                        ),
                                      ),
                                    )
                                    .toList()
                                : const <Map<String, String>>[];
                            final cardBg = theme.brightness == Brightness.dark
                                ? cs.surfaceContainerHighest
                                : cs.surfaceContainerLow;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              elevation: 0,
                              color: cardBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: SelectionArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'file_backup_run_record_heading'
                                            .trParams({
                                          'id':
                                              row['id']?.toString() ??
                                              '${list.length - i}',
                                        }),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: cs.onSurface,
                                              fontWeight: FontWeight.w600,
                                              height: 1.15,
                                            ),
                                        textHeightBehavior: _tightTextHeight,
                                      ),
                                      const SizedBox(height: 2),
                                      _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_start'.tr,
                                      _formatLocalTime(row['start_time']),
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_end'.tr,
                                      row['end_time'] == null
                                          ? 'file_backup_run_records_na'.tr
                                          : _formatLocalTime(row['end_time']),
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_status'.tr,
                                      _recordStatusText(
                                        row['status']?.toString() ?? '',
                                      ),
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_duration_ms'.tr,
                                      _formatDurationMs(row['duration_ms']),
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_files_copied'.tr,
                                      '${row['files_copied_count'] ?? 0}',
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_files_skipped'.tr,
                                      '${row['files_skipped_count'] ?? 0}',
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_files_removed'.tr,
                                      '${row['files_removed_count'] ?? 0}',
                                    ),
                                    _kv(
                                      theme,
                                      cs,
                                      'file_backup_run_record_bytes_copied'.tr,
                                      _formatBytes(row['bytes_copied_count']),
                                    ),
                                    _errorFilesSummaryRow(
                                      context,
                                      theme,
                                      cs,
                                      errors,
                                    ),
                                  ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Get.back<void>(),
                  child: Text('ok'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
