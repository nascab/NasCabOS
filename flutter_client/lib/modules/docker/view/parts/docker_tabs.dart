part of '../docker_manager_view.dart';

class _OverviewTab extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _OverviewTab({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final status = controller.status;
      final cards = [
        (
          'docker_status_containers',
          '${status['containers'] ?? 0}',
          Icons.inventory_2_outlined,
        ),
        (
          'docker_status_running',
          '${status['containersRunning'] ?? 0}',
          Icons.play_circle_outline,
        ),
        (
          'docker_status_images',
          '${status['images'] ?? 0}',
          Icons.layers_outlined,
        ),
        (
          'docker_status_version',
          status['serverVersion']?.toString().trim().isNotEmpty == true
              ? status['serverVersion'].toString()
              : '--',
          Icons.extension_outlined,
        ),
      ];

      return ListView(
        key: const ValueKey('docker_overview'),
        padding: EdgeInsets.all(appMode ? 12 : 20),
        children: [
          ...cards.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: CustomGlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.$3, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1.tr,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.$2,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          CustomGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'docker_engine_info'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _KvRow(
                  label: 'docker_status_host'.tr,
                  value: '${status['dockerHost'] ?? 'local'}',
                ),
                _KvRow(
                  label: 'docker_status_os'.tr,
                  value: '${status['operatingSystem'] ?? '--'}',
                ),
                _KvRow(
                  label: 'docker_status_arch'.tr,
                  value: '${status['architecture'] ?? '--'}',
                ),
                _KvRow(
                  label: 'docker_status_name'.tr,
                  value: '${status['name'] ?? '--'}',
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _ImagesTab extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _ImagesTab({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final items = controller.images;
      return ListView(
        key: const ValueKey('docker_images'),
        padding: EdgeInsets.fromLTRB(
          appMode ? 12 : 20,
          0,
          appMode ? 12 : 20,
          appMode ? 12 : 20,
        ),
        children: [
          _SectionHeader(
            title: 'docker_tab_images'.tr,
            subtitle: 'docker_images_subtitle'.tr,
            actions: [
              CustomButton(
                text: 'refresh'.tr,
                isPrimary: false,
                icon: const Icon(Icons.refresh_outlined),
                onPressed: () => controller.refreshImages(showLoading: false),
              ),
              CustomButton(
                text: 'docker_pull_image'.tr,
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _showPullImageDialog(context, controller),
              ),
              CustomButton(
                text: 'docker_import_image'.tr,
                icon: const Icon(Icons.upload_file_outlined),
                isPrimary: false,
                onPressed: () => _showImportImageDialog(context, controller),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const CustomGlassCard(
              padding: EdgeInsets.all(20),
              child: CustomNoData(),
            )
          else
            ...items.map((item) {
              final reference =
                  item['reference']?.toString().trim().isNotEmpty == true
                  ? item['reference'].toString()
                  : item['id']?.toString() ?? '--';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CustomGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  reference,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item['id']?.toString() ?? '--',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'RobotoMono',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'copy') {
                                await controller.copyCommand(
                                  'docker pull ${item['reference'] ?? item['id']}',
                                );
                              } else if (value == 'retag') {
                                await _showTagImageDialog(
                                  context,
                                  controller,
                                  item,
                                );
                              } else if (value == 'delete') {
                                final ok = await DialogUtil.showConfirmDialog(
                                  title: 'need_confirm'.tr,
                                  content: 'docker_delete_image_confirm'.tr,
                                  confirmText: 'delete'.tr,
                                  cancelText: 'cancel'.tr,
                                );
                                if (ok == true) {
                                  await controller.deleteImage(
                                    item['id']?.toString() ?? '',
                                    reference:
                                        item['reference']?.toString() ?? '',
                                  );
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem<String>(
                                value: 'copy',
                                child: Text('docker_copy_pull_command'.tr),
                              ),
                              PopupMenuItem<String>(
                                value: 'retag',
                                child: Text('docker_change_tag'.tr),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('delete'.tr),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _MetaLine(
                        label: 'name'.tr,
                        value: item['repository']?.toString() ?? '--',
                      ),
                      _MetaLine(
                        label: 'docker_tag'.tr,
                        value: item['tag']?.toString() ?? '--',
                      ),
                      _MetaLine(
                        label: 'size'.tr,
                        value: item['size']?.toString() ?? '--',
                      ),
                      _MetaLine(
                        label: 'create_time'.tr,
                        value: item['createdAt']?.toString() ?? '--',
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );
    });
  }
}

class _ContainersTab extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _ContainersTab({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = controller.containers;
      final filters = [
        ('', 'docker_filter_all'),
        ('running', 'docker_filter_running'),
        ('exited', 'docker_filter_exited'),
      ];
      return ListView(
        key: const ValueKey('docker_containers'),
        padding: EdgeInsets.fromLTRB(
          appMode ? 12 : 20,
          0,
          appMode ? 12 : 20,
          appMode ? 12 : 20,
        ),
        children: [
          _SectionHeader(
            title: 'docker_tab_containers'.tr,
            subtitle: 'docker_containers_subtitle'.tr,
            actions: [
              CustomButton(
                text: 'refresh'.tr,
                isPrimary: false,
                icon: const Icon(Icons.refresh_outlined),
                onPressed: () =>
                    controller.refreshContainers(showLoading: false),
              ),
              CustomButton(
                text: 'docker_create_container'.tr,
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () =>
                    _showCreateContainerDialog(context, controller),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: filters
                .map((item) {
                  final selected =
                      controller.containerStatusFilter.value == item.$1;
                  return ChoiceChip(
                    label: Text(item.$2.tr),
                    selected: selected,
                    onSelected: (_) async {
                      controller.containerStatusFilter.value = item.$1;
                      await controller.refreshContainers(showLoading: false);
                    },
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const CustomGlassCard(
              padding: EdgeInsets.all(20),
              child: CustomNoData(),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ContainerCard(
                  controller: controller,
                  item: item,
                  appMode: appMode,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ContainerCard extends StatelessWidget {
  final DockerController controller;
  final Map<String, dynamic> item;
  final bool appMode;

  const _ContainerCard({
    required this.controller,
    required this.item,
    required this.appMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = item['state']?.toString().trim() ?? '';
    final status = item['status']?.toString().trim() ?? '';
    final ports = item['ports'] is List ? item['ports'] as List : const [];
    final mounts = item['mounts'] is List ? item['mounts'] as List : const [];
    final isRunning = state == 'running';
    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.green.withValues(alpha: 0.10)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isNotEmpty ? status : state,
        style: theme.textTheme.labelLarge?.copyWith(
          color: isRunning
              ? Colors.green.shade700
              : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return CustomGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (appMode) ...[statusBadge, const SizedBox(height: 10)],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          item['name']?.toString() ?? '--',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['image']?.toString() ?? '--',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['id']?.toString() ?? '--',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'RobotoMono',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!appMode) ...[const SizedBox(width: 12), statusBadge],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (ports.isNotEmpty) ...[
            Text(
              'docker_ports'.tr,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ports
                    .map((port) {
                      final map = port is Map ? port : const {};
                      final hostIp = map['hostIp']?.toString() ?? '';
                      final hostPort = map['hostPort']?.toString() ?? '';
                      final containerPort =
                          map['containerPort']?.toString() ?? '';
                      final protocol =
                          map['protocol']?.toString().toLowerCase() ?? 'tcp';
                      final normalizedContainerPort =
                          containerPort.contains('/')
                          ? containerPort
                          : '$containerPort/$protocol';
                      final text = hostPort.isEmpty
                          ? normalizedContainerPort
                          : '${hostIp.isEmpty ? '' : '$hostIp:'}$hostPort -> $normalizedContainerPort';
                      return _ContainerInfoTag(text: text);
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (mounts.isNotEmpty) ...[
            Text(
              'docker_mounts'.tr,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: mounts
                    .map((mount) {
                      final map = mount is Map ? mount : const {};
                      final source = map['source']?.toString() ?? '--';
                      final target = map['target']?.toString() ?? '--';
                      final readOnly = map['readOnly'] == true;
                      return _ContainerInfoTag(
                        text: '$source -> $target${readOnly ? ' (ro)' : ''}',
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              CustomButton(
                text: isRunning ? 'docker_stop'.tr : 'docker_start'.tr,
                icon: Icon(
                  isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                ),
                onPressed: () async {
                  if (isRunning) {
                    await controller.stopContainer(
                      item['id']?.toString() ?? '',
                    );
                  } else {
                    await controller.startContainer(
                      item['id']?.toString() ?? '',
                    );
                  }
                },
              ),
              CustomButton(
                text: 'docker_view_logs'.tr,
                isPrimary: false,
                icon: const Icon(Icons.subject_outlined),
                onPressed: () => _showLogsDialog(context, controller, item),
              ),
              CustomButton(
                text: 'delete'.tr,
                isPrimary: false,
                icon: const Icon(Icons.delete_outline),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: theme.colorScheme.error,
                  minimumSize: const Size(80, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final force = await DialogUtil.showConfirmDialog(
                    title: 'need_confirm'.tr,
                    content: 'docker_delete_container_confirm'.tr,
                    confirmText: 'delete'.tr,
                    cancelText: 'cancel'.tr,
                  );
                  if (force == true) {
                    await controller.deleteContainer(
                      item['id']?.toString() ?? '',
                      force: true,
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _TasksTab({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = controller.tasks.toList(growable: false);
      final selectedId = controller.selectedTaskId.value.trim();
      final tasksVersion = list
          .map((task) {
            final id = task['id']?.toString() ?? '';
            final status =
                task['status']?.toString().trim().toLowerCase() ?? '';
            final progress = task['progress']?.toString() ?? '';
            return '$id:$status:$progress';
          })
          .join('|');
      return LayoutBuilder(
        key: ValueKey('docker_tasks_$tasksVersion'),
        builder: (context, constraints) {
          final wide = !appMode && constraints.maxWidth > 980;
          final left = ListView(
            key: ValueKey('docker_tasks_list_$tasksVersion'),
            padding: EdgeInsets.fromLTRB(
              appMode ? 12 : 20,
              0,
              appMode ? 12 : 20,
              appMode ? 12 : 20,
            ),
            children: [
              _SectionHeader(
                title: 'docker_tab_tasks'.tr,
                subtitle: 'docker_tasks_subtitle'.tr,
                actions: [
                  CustomButton(
                    text: 'refresh'.tr,
                    isPrimary: false,
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: () =>
                        controller.refreshTasks(showLoading: false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const CustomGlassCard(
                  padding: EdgeInsets.all(20),
                  child: CustomNoData(),
                )
              else
                ...list.map((task) {
                  final selected = selectedId == (task['id']?.toString() ?? '');
                  final taskId = task['id']?.toString() ?? '';
                  final status =
                      task['status']?.toString().trim().toLowerCase() ?? '--';
                  final progress = task['progress'];
                  final cmd = task['command']?.toString().trim() ?? '';
                  final canCancel = status == 'queued' || status == 'running';
                  final canDelete = !canCancel;
                  final stopText = status == 'running'
                      ? 'docker_stop'.tr
                      : 'cancel'.tr;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CustomGlassCard(
                      key: ValueKey(
                        '$taskId-$status-${progress?.toString() ?? ''}-$selected',
                      ),
                      onTap: () {
                        controller.selectTask(taskId, clearLogs: true);
                      },
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task['title']?.toString() ?? '--',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              _StatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _translateTaskType(task['type']?.toString() ?? ''),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          if (progress is num) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: progress.clamp(0, 100).toDouble() / 100,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              CustomButton(
                                text: 'docker_view_logs'.tr,
                                isPrimary: false,
                                onPressed: () async {
                                  await controller.openTaskLogs(
                                    taskId,
                                    showLoading: false,
                                    enablePolling: !wide,
                                  );
                                  if (context.mounted && !wide) {
                                    await _showTaskLogsSheet(
                                      context,
                                      controller,
                                    );
                                  }
                                },
                              ),
                              if (cmd.isNotEmpty)
                                CustomButton(
                                  text: 'docker_copy_command'.tr,
                                  isPrimary: false,
                                  onPressed: () => controller.copyCommand(cmd),
                                ),
                              if (canCancel)
                                CustomButton(
                                  key: ValueKey('task-cancel-$taskId-$status'),
                                  text: stopText,
                                  isPrimary: false,
                                  onPressed: () =>
                                      controller.cancelTask(taskId),
                                ),
                              if (canDelete)
                                CustomButton(
                                  key: ValueKey('task-delete-$taskId-$status'),
                                  text: 'delete'.tr,
                                  isPrimary: false,
                                  onPressed: () =>
                                      controller.deleteTask(taskId),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );

          if (!wide) return left;

          return Row(
            children: [
              Expanded(child: left),
              SizedBox(
                width: 420,
                child: _TaskLogsPanel(controller: controller),
              ),
            ],
          );
        },
      );
    });
  }
}

class _TaskLogsPanel extends StatelessWidget {
  final DockerController controller;
  final bool showLeftBorder;

  const _TaskLogsPanel({required this.controller, this.showLeftBorder = true});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final taskId = controller.selectedTaskId.value.trim();
      final task = controller.tasks.firstWhereOrNull(
        (item) => (item['id']?.toString() ?? '') == taskId,
      );
      final logsText = controller.taskLogs
          .map((item) => _formatTaskLogLine(item))
          .join('\n');
      return Container(
        decoration: BoxDecoration(
          border: showLeftBorder
              ? Border(left: BorderSide(color: Theme.of(context).dividerColor))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: task == null
              ? Center(child: Text('docker_select_task_hint'.tr))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      task['title']?.toString() ?? '--',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      task['command']?.toString() ?? '--',
                      maxLines: 3,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'docker_view_logs'.tr,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (logsText.trim().isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _copyText(logsText),
                            icon: const Icon(Icons.copy_all_outlined, size: 18),
                            label: Text('copy'.tr),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: controller.taskLogs.isEmpty
                            ? Center(child: Text('no_data'.tr))
                            : SelectionArea(
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: controller.taskLogs.length,
                                  itemBuilder: (_, index) {
                                    final item = controller.taskLogs[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: SelectableText(
                                        _formatTaskLogLine(item),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontFamily: 'RobotoMono',
                                            ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    });
  }
}

class _SettingsTab extends StatelessWidget {
  final DockerController controller;

  const _SettingsTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final config = controller.config;
      final configPath = config['path']?.toString().trim().isNotEmpty == true
          ? config['path'].toString()
          : '--';
      final exists = config['exists'] == true;
      final jsonValid = config['jsonValid'] != false;
      final validationMessage =
          config['validationMessage']?.toString().trim() ?? '';
      return ListView(
        key: const ValueKey('docker_settings'),
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader(
            title: 'docker_config_file'.tr,
            subtitle: 'docker_config_file_subtitle'.tr,
            actions: [
              CustomButton(
                text: 'refresh'.tr,
                isPrimary: false,
                icon: const Icon(Icons.refresh_outlined),
                onPressed: () => controller.refreshConfig(showLoading: false),
              ),
              // CustomButton(
              //   text: controller.dockerAvailable.value
              //       ? 'docker_stop_service'.tr
              //       : 'docker_start_service'.tr,
              //   isPrimary: false,
              //   isDisabled: controller.dockerServiceOperating.value,
              //   icon: Icon(
              //     controller.dockerAvailable.value
              //         ? Icons.stop_circle_outlined
              //         : Icons.play_circle_outline,
              //   ),
              //   onPressed: () => controller.toggleDockerService(),
              // ),
              CustomButton(
                text: 'edit'.tr,
                icon: const Icon(Icons.edit_note_outlined),
                onPressed: () => _showConfigEditorDialog(context, controller),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KvRow(label: 'docker_config_path'.tr, value: configPath),
                  _KvRow(
                    label: 'docker_config_exists'.tr,
                    value: exists ? 'yes'.tr : 'no'.tr,
                  ),
                  _KvRow(
                    label: 'docker_json_status'.tr,
                    value: jsonValid
                        ? 'docker_json_valid'.tr
                        : 'docker_json_invalid'.tr,
                  ),
                  if (!jsonValid && validationMessage.isNotEmpty)
                    _KvRow(label: 'tip'.tr, value: validationMessage),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      config['content']?.toString() ?? '{\n}\n',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              );
      },
    );
  }
}
