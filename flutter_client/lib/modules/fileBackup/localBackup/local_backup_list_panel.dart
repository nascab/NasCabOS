part of '../backupMain/file_backup_view.dart';

class _LocalBackupPanel extends StatelessWidget {
  const _LocalBackupPanel();

  Future<void> _showLogsDialog(
    BuildContext context,
    LocalBackupController ctrl,
    LocalBackupProfile profile,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LocalBackupLogsDialog(ctrl: ctrl, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final compact = DeviceUtils.isPhone(context);
    final edgePadding = compact ? EdgeInsets.zero : const EdgeInsets.all(12);

    Widget buildContent(LocalBackupController ctrl) {
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
                          'local_backup_menu'.tr,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'local_backup_help_tooltip'.tr,
                        child: const Icon(Icons.help_outline, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'refresh'.tr,
                  onPressed: ctrl.refreshProfiles,
                  isPrimary: false,
                  icon: const Icon(Icons.refresh_outlined),
                ),
                const SizedBox(width: 8),
                CustomButton(
                  text: 'create'.tr,
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => _LocalBackupDialog(ctrl: ctrl),
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
            SliverPadding(
              padding: edgePadding.copyWith(bottom: 6),
              sliver: SliverToBoxAdapter(child: buildHeader()),
            ),
            Obx(() {
              final loading = ctrl.isLoading.value;
              final list = ctrl.profiles;
              if (loading && list.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (list.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: CustomNoData(),
                );
              }
              return SliverPadding(
                padding: edgePadding.copyWith(top: 0),
                sliver: SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final rt = ctrl.runtimeOf(p.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LocalBackupListItemCard(
                      ctrl: ctrl,
                      profile: p,
                      runtime: rt,
                      onShowLogs: () => _showLogsDialog(context, ctrl, p),
                      onEdit: () async {
                        await showDialog<bool>(
                          context: context,
                          builder: (_) =>
                              _LocalBackupDialog(ctrl: ctrl, initial: p),
                        );
                      },
                      onDelete: () async {
                        final confirmed = await DialogUtil.showConfirmDialog(
                          title: 'need_confirm'.tr,
                          content: 'local_backup_delete_confirm'.trParams({
                            'name': p.name,
                          }),
                          confirmText: 'ok'.tr,
                          cancelText: 'cancel'.tr,
                        );
                        if (confirmed != true) return;
                        await ctrl.deleteProfile(p.id);
                      },
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

    if (Get.isRegistered<LocalBackupController>()) {
      return GetBuilder<LocalBackupController>(builder: buildContent);
    }
    return GetBuilder<LocalBackupController>(
      init: LocalBackupController(),
      builder: buildContent,
    );
  }
}

class _LocalBackupListItemCard extends StatelessWidget {
  final LocalBackupController ctrl;
  final LocalBackupProfile profile;
  final LocalBackupRuntime runtime;
  final VoidCallback onShowLogs;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  const _LocalBackupListItemCard({
    required this.ctrl,
    required this.profile,
    required this.runtime,
    required this.onShowLogs,
    required this.onEdit,
    required this.onDelete,
  });

  String _statusText(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'running') return 'local_backup_status_running'.tr;
    if (s == 'error') return 'local_backup_status_error'.tr;
    return 'local_backup_status_idle'.tr;
  }

  Color _statusColor(ThemeData theme, String status) {
    final s = status.trim().toLowerCase();
    if (s == 'running') return theme.colorScheme.primary;
    if (s == 'error') return theme.colorScheme.error;
    return theme.colorScheme.onSurface.withValues(alpha: 0.65);
  }

  String _formatLocalTimeMs(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _freqText(LocalBackupProfile p) {
    if (p.realtime) {
      return 'local_backup_frequency_realtime'.tr;
    }
    final m = p.intervalMinutes <= 0 ? 60 : p.intervalMinutes;
    return 'local_backup_frequency_interval'.trParams({'minutes': '$m'});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile;
    final rt = runtime;
    final isCurrentServer = ctrl.currentServerId == p.serverId;

    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Obx(() {
          final status = rt.status.value;
          final busy = rt.busy.value;
          final canEdit = isCurrentServer && !busy;
          final runDisabledTooltip = isCurrentServer
              ? null
              : 'local_backup_not_current_server_tooltip'.tr;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${p.name} · #${p.id}',
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
                label: 'local_backup_source_dir'.tr,
                value: p.sourceDir,
              ),
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'local_backup_target_dir'.tr,
                value: p.targetDir,
                viewPath: p.targetDir,
              ),
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'local_backup_auto_backup'.tr,
                value: p.enabled ? 'enabled'.tr : 'disabled'.tr,
              ),
              if (p.enabled) ...[
                const SizedBox(height: 6),
                _KeyValueRow(
                  label: 'local_backup_frequency'.tr,
                  value: _freqText(p),
                ),
              ],
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'local_backup_last_run'.tr,
                value: _formatLocalTimeMs(rt.lastRunAtMs.value),
              ),
              const SizedBox(height: 6),
              _KeyValueRow(
                label: 'local_backup_last_success'.tr,
                value: _formatLocalTimeMs(rt.lastSuccessAtMs.value),
              ),
              if (rt.lastError.value.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _KeyValueRow(
                  label: 'local_backup_last_error'.tr,
                  value: rt.lastError.value.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  selectable: false,
                ),
              ],
              if (busy) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: rt.progress, minHeight: 6),
                const SizedBox(height: 6),
                Text(
                  'local_backup_progress_text'.trParams({
                    'done': '${rt.processedFiles.value}',
                    'total': '${rt.totalFiles.value}',
                    'bytesDone': UploadTransferHelper.formatBytes(
                      rt.processedBytes.value,
                    ),
                    'bytesTotal': UploadTransferHelper.formatBytes(
                      rt.totalBytes.value,
                    ),
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                if (rt.currentRelPath.value.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      rt.currentRelPath.value.trim(),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  if (busy)
                    _IconActionButton(
                      tooltip: isCurrentServer
                          ? 'file_backup_stop'.tr
                          : 'local_backup_not_current_server_tooltip'.tr,
                      icon: Icons.stop_circle_outlined,
                      onPressed: isCurrentServer
                          ? () => ctrl.stopBackup(p.id)
                          : null,
                    ),
                  _IconActionButton(
                    tooltip: runDisabledTooltip ?? 'local_backup_backup_new'.tr,
                    icon: Icons.cloud_upload_outlined,
                    onPressed: isCurrentServer && !busy
                        ? () => ctrl.backupNew(p.id)
                        : null,
                  ),
                  _IconActionButton(
                    tooltip: runDisabledTooltip ?? 'local_backup_backup_all'.tr,
                    icon: Icons.upload_outlined,
                    onPressed: isCurrentServer && !busy
                        ? () => ctrl.backupAll(p.id)
                        : null,
                  ),
                  _IconActionButton(
                    tooltip: 'local_backup_logs'.tr,
                    icon: Icons.list_alt_outlined,
                    onPressed: onShowLogs,
                  ),
                  _IconActionButton(
                    tooltip: runDisabledTooltip ?? 'edit'.tr,
                    icon: Icons.edit_outlined,
                    onPressed: canEdit ? () async => await onEdit() : null,
                  ),
                  _IconActionButton(
                    tooltip:
                        runDisabledTooltip ?? 'local_backup_cleanup_tooltip'.tr,
                    icon: Icons.cleaning_services_outlined,
                    onPressed: isCurrentServer && !busy
                        ? () async {
                            await showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => _LocalBackupCleanupDiffDialog(
                                ctrl: ctrl,
                                profile: p,
                              ),
                            );
                          }
                        : null,
                  ),
                  _IconActionButton(
                    tooltip: 'delete'.tr,
                    icon: Icons.delete_outline,
                    onPressed: busy ? null : () async => await onDelete(),
                  ),
                ],
              ),
            ],
          );
        }),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _IconActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _LocalBackupCleanupDiffDialog extends StatefulWidget {
  final LocalBackupController ctrl;
  final LocalBackupProfile profile;

  const _LocalBackupCleanupDiffDialog({
    required this.ctrl,
    required this.profile,
  });

  @override
  State<_LocalBackupCleanupDiffDialog> createState() =>
      _LocalBackupCleanupDiffDialogState();
}

class _LocalBackupCleanupDiffDialogState
    extends State<_LocalBackupCleanupDiffDialog> {
  bool _detecting = false;
  bool _deleting = false;
  bool _hasDetected = false;
  String _error = '';
  LocalBackupCleanupProgress? _progress;
  List<LocalBackupCleanupEntry> _items = const <LocalBackupCleanupEntry>[];
  Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _detect();
    });
  }

  @override
  void dispose() {
    widget.ctrl.cancelCleanup(widget.profile.id);
    super.dispose();
  }

  Future<void> _detect() async {
    if (_detecting || _deleting) return;
    widget.ctrl.cancelCleanup(widget.profile.id);
    setState(() {
      _detecting = true;
      _hasDetected = true;
      _error = '';
      _progress = null;
      _items = const <LocalBackupCleanupEntry>[];
      _selected = <String>{};
    });

    try {
      final res = await widget.ctrl.detectCleanupDiff(
        widget.profile,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _items = res;
        _selected = res.map((e) => e.serverPath).toSet();
      });
    } catch (e) {
      if (e is LocalBackupCleanupCancelled) return;
      if (!mounted) return;
      setState(() => _error = e.toString().trim());
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  void _selectAll() {
    setState(() => _selected = _items.map((e) => e.serverPath).toSet());
  }

  void _invertSelect() {
    final all = _items.map((e) => e.serverPath).toSet();
    setState(() => _selected = all.difference(_selected));
  }

  Future<void> _deleteSelected() async {
    if (_detecting || _deleting) return;
    final targets = _items
        .where((e) => _selected.contains(e.serverPath))
        .toList();
    if (targets.isEmpty) return;

    final count = targets.length;
    final isShellSupported = ApiController.instance.state.shellSupported;

    bool? recycle;
    if (isShellSupported) {
      final choice = await DialogUtil.showConfirmThreeButtonsDialog(
        title: 'need_confirm'.tr,
        content: 'local_backup_cleanup_delete_confirm'.trParams({
          'count': '$count',
        }),
        cancelText: 'cancel'.tr,
        option1Text: 'delete'.tr,
        option2Text: 'put_in_recycle_bin'.tr,
        option2IsPrimary: true,
      );
      if (choice == null) return;
      recycle = choice == 1;
    } else {
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'local_backup_cleanup_delete_confirm'.trParams({
          'count': '$count',
        }),
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed != true) return;
      recycle = false;
    }

    setState(() => _deleting = true);
    try {
      final paths = targets.map((e) => e.serverPath).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final ok = await widget.ctrl.deleteServerEntries(paths, recycle: recycle);
      if (!ok) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      if (!mounted) return;
      final removed = paths.toSet();
      setState(() {
        _items = _items.where((e) => !removed.contains(e.serverPath)).toList();
        _selected.removeWhere((e) => removed.contains(e));
      });
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Widget _iconFor(bool isDir) {
    final asset = isDir
        ? 'assets/icons/file/folder.png'
        : 'assets/icons/file/file.png';
    return Image.asset(asset, width: 20, height: 20);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selected.length;
    final totalCount = _items.length;

    Widget body;
    if (_detecting) {
      final p = _progress;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('local_backup_cleanup_detecting'.tr)),
              TextButton(
                onPressed: () => widget.ctrl.cancelCleanup(widget.profile.id),
                child: Text('cancel'.tr),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (p != null) ...[
            Text(
              'local_backup_cleanup_progress_dir'.trParams({
                'dir': p.currentServerDir,
              }),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              'local_backup_cleanup_progress_counts'.trParams({
                'dirs': '${p.scannedDirs}',
                'items': '${p.scannedItems}',
                'orphans': '${p.orphanedFound}',
              }),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      );
    } else if (_error.isNotEmpty) {
      body = SingleChildScrollView(
        child: SelectableText(
          _error,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    } else if (!_hasDetected) {
      body = Text('local_backup_cleanup_intro'.tr);
    } else if (_items.isEmpty) {
      body = CustomNoData(text: 'local_backup_cleanup_empty'.tr);
    } else {
      body = Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'local_backup_cleanup_summary'.trParams({
                    'selected': '$selectedCount',
                    'total': '$totalCount',
                  }),
                ),
              ),
              TextButton(
                onPressed: _deleting ? null : _selectAll,
                child: Text('local_backup_cleanup_select_all'.tr),
              ),
              TextButton(
                onPressed: _deleting ? null : _invertSelect,
                child: Text('local_backup_cleanup_invert_select'.tr),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = _items[i];
                final checked = _selected.contains(it.serverPath);
                return ListTile(
                  dense: true,
                  leading: _iconFor(it.isDir),
                  title: Text(
                    it.relPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    it.serverPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                  trailing: Checkbox(
                    value: checked,
                    onChanged: _deleting
                        ? null
                        : (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(it.serverPath);
                              } else {
                                _selected.remove(it.serverPath);
                              }
                            });
                          },
                  ),
                  onTap: _deleting
                      ? null
                      : () {
                          setState(() {
                            if (checked) {
                              _selected.remove(it.serverPath);
                            } else {
                              _selected.add(it.serverPath);
                            }
                          });
                        },
                );
              },
            ),
          ),
        ],
      );
    }

    return DialogUtil.createAlertDialog(
      title: Text(
        'local_backup_cleanup_title'.trParams({'name': widget.profile.name}),
      ),
      constraints: const BoxConstraints(
        maxHeight: 700,
        maxWidth: 820,
        minWidth: 520,
      ),
      content: SizedBox(width: 760, height: 560, child: body),
      actions: [
        TextButton(
          onPressed: (_detecting || _deleting) ? null : _detect,
          child: Text('local_backup_cleanup_detect'.tr),
        ),
        TextButton(
          onPressed: (_detecting || _deleting || _selected.isEmpty)
              ? null
              : _deleteSelected,
          child: Text('local_backup_cleanup_delete'.tr),
        ),
        TextButton(
          onPressed: (_detecting || _deleting) ? null : () => Get.back(),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}

class _LocalBackupLogsDialog extends StatefulWidget {
  final LocalBackupController ctrl;
  final LocalBackupProfile profile;

  const _LocalBackupLogsDialog({required this.ctrl, required this.profile});

  @override
  State<_LocalBackupLogsDialog> createState() => _LocalBackupLogsDialogState();
}

class _LocalBackupLogsDialogState extends State<_LocalBackupLogsDialog> {
  static const int _pageSize = 200;
  final ScrollController _scrollController = ScrollController();

  final List<LocalBackupUploadLog> _logs = <LocalBackupUploadLog>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String _error = '';
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _formatLocalTimeMs(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final now = _scrollController.position.pixels;
    if (now >= max - 240) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _error = '';
      _offset = 0;
      _logs.clear();
    });
    await _loadMore();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _error = '';
    });
    try {
      final rows = await widget.ctrl.listLogs(
        widget.profile.id,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _logs.addAll(rows);
        _offset += rows.length;
        if (rows.length < _pageSize) _hasMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().trim();
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color statusColor(String s) {
      final v = s.trim().toLowerCase();
      if (v == 'success') return theme.colorScheme.primary;
      if (v == 'error') return theme.colorScheme.error;
      return theme.colorScheme.onSurface.withValues(alpha: 0.65);
    }

    Widget body;
    if (_loading && _logs.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty && _logs.isEmpty) {
      body = SingleChildScrollView(
        child: SelectableText(
          _error,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    } else if (_logs.isEmpty) {
      body = const CustomNoData();
    } else {
      body = ListView.separated(
        controller: _scrollController,
        itemCount: _logs.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i >= _logs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final it = _logs[i];
          final time = _formatLocalTimeMs(it.finishedAtMs);
          final status = it.status.trim().toLowerCase();
          final err = it.error.trim();
          final sizeText = UploadTransferHelper.formatBytes(it.size);
          return ListTile(
            dense: true,
            leading: Icon(
              status == 'success'
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: statusColor(status),
            ),
            title: Text(it.relPath),
            subtitle: Text(
              '$time · $sizeText${err.isEmpty ? '' : '\n$err'}',
              maxLines: err.isEmpty ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    }

    return DialogUtil.createAlertDialog(
      title: Text(
        'local_backup_logs_title'.trParams({'name': widget.profile.name}),
      ),
      constraints: const BoxConstraints(
        maxHeight: 620,
        maxWidth: 820,
        minWidth: 520,
      ),
      content: SizedBox(width: 760, height: 520, child: body),
      actions: [
        TextButton(
          onPressed: _loadingMore
              ? null
              : () async {
                  final confirmed = await DialogUtil.showConfirmDialog(
                    title: 'need_confirm'.tr,
                    content: 'local_backup_logs_clear_confirm'.tr,
                    confirmText: 'ok'.tr,
                    cancelText: 'cancel'.tr,
                  );
                  if (confirmed != true) return;
                  await widget.ctrl.clearLogs(widget.profile.id);
                  if (!mounted) return;
                  await _reload();
                },
          child: Text('local_backup_logs_clear'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('close'.tr),
        ),
      ],
    );
  }
}
