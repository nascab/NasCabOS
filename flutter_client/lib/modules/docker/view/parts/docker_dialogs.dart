part of '../docker_manager_view.dart';

// ============================================================
// Dialog functions & dialog-related widgets
// ============================================================

Future<void> _showPullImageDialog(
  BuildContext context,
  DockerController controller,
) async {
  final registryCtrl = TextEditingController();
  final imageCtrl = TextEditingController();
  final tagCtrl = TextEditingController(text: 'latest');
  final userCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text('docker_pull_image'.tr),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: registryCtrl,
                  decoration: InputDecoration(
                    labelText:
                        '${'docker_registry'.tr} (${'user_mgmt_optional_hint'.tr})',
                    hintText: 'docker_registry_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: imageCtrl,
                  decoration: InputDecoration(
                    labelText: 'docker_image_name'.tr,
                    hintText: 'docker_image_name_hint'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagCtrl,
                  decoration: InputDecoration(
                    labelText: 'docker_tag'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: InputDecoration(
                    labelText:
                        '${'docker_registry_username'.tr} (${'user_mgmt_optional_hint'.tr})',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText:
                        '${'docker_registry_password'.tr} (${'user_mgmt_optional_hint'.tr})',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              if (imageCtrl.text.trim().isEmpty) {
                ToastUtil.show('docker_image_name_required'.tr);
                return;
              }
              final ok = await controller.pullImage(
                image: imageCtrl.text.trim(),
                registry: registryCtrl.text.trim(),
                tag: tagCtrl.text.trim(),
                username: userCtrl.text.trim(),
                password: passwordCtrl.text,
              );
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('docker_start_pull'.tr),
          ),
        ],
      );
    },
  );
}

Future<void> _showCreateContainerDialog(
  BuildContext context,
  DockerController controller,
) async {
  final nameCtrl = TextEditingController();
  final commandCtrl = TextEditingController();
  final cpuCtrl = TextEditingController();
  final memoryCtrl = TextEditingController();
  var imageOptions = _buildCreateContainerImageOptions(controller.images);
  String? selectedImageId = imageOptions.isNotEmpty
      ? imageOptions.first['id']?.toString()
      : null;
  var restartPolicy = 'unless-stopped';
  var advancedMode = false;
  final envItems = <Map<String, dynamic>>[];
  final portItems = <Map<String, dynamic>>[];
  final volumeItems = <Map<String, dynamic>>[];

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final selectedImage = imageOptions.firstWhereOrNull(
            (item) => item['id']?.toString() == selectedImageId,
          );
          return DialogUtil.createAlertDialog(
            title: Text('docker_create_container'.tr),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedImageId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'docker_image_name'.tr,
                        border: const OutlineInputBorder(),
                      ),
                      items: imageOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id']?.toString(),
                              child: Text(item['label']?.toString() ?? '--'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: imageOptions.isEmpty
                          ? null
                          : (value) {
                              setState(() {
                                selectedImageId = value;
                              });
                            },
                    ),
                    if (selectedImage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'SHA256: ${selectedImage['id'] ?? '--'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'RobotoMono',
                        ),
                      ),
                    ],
                    if (imageOptions.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No local image available. Pull an image first.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _CreateModeToggle(
                      advancedMode: advancedMode,
                      onChanged: (value) {
                        setState(() {
                          advancedMode = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'docker_container_name'.tr,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: restartPolicy,
                      decoration: InputDecoration(
                        labelText: 'docker_restart_policy'.tr,
                        border: const OutlineInputBorder(),
                      ),
                      items: _restartPolicyOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.$1,
                              child: Text(item.$2.tr),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          restartPolicy = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _CreateListSection(
                      title: 'docker_ports'.tr,
                      subtitle: 'docker_ports_section_hint'.tr,
                      emptyText: '',
                      addButtonText: '',
                      onAdd: () {},
                      headerTrailing: const SizedBox.shrink(),
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                      children: [
                        _CreateTagGrid(
                          items: portItems
                              .asMap()
                              .entries
                              .map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                final hostIp = item['hostIp']?.toString() ?? '';
                                final hostPort =
                                    item['hostPort']?.toString() ?? '';
                                final containerPort =
                                    item['containerPort']?.toString() ?? '';
                                return _CreateEditorTag(
                                  label:
                                      '${hostIp.isEmpty ? '' : '$hostIp:'}$hostPort -> $containerPort',
                                  caption: '',
                                  onTap: () async {
                                    final updated =
                                        await _showPortBindingEditorDialog(
                                          dialogContext,
                                          initialValue: item,
                                        );
                                    if (updated == null) return;
                                    setState(() {
                                      portItems[index] = updated;
                                    });
                                  },
                                  onDelete: () {
                                    setState(() {
                                      portItems.removeAt(index);
                                    });
                                  },
                                );
                              })
                              .toList(growable: false),
                          addLabel: '${'add'.tr} ${'docker_ports'.tr}',
                          onAdd: () async {
                            final created = await _showPortBindingEditorDialog(
                              dialogContext,
                            );
                            if (created == null) return;
                            setState(() {
                              portItems.add(created);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CreateListSection(
                      title: 'docker_mounts'.tr,
                      subtitle: 'docker_mounts_section_hint'.tr,
                      emptyText: '',
                      addButtonText: '',
                      onAdd: () {},
                      headerTrailing: const SizedBox.shrink(),
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                      children: [
                        _CreateTagGrid(
                          items: volumeItems
                              .asMap()
                              .entries
                              .map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                return _CreateEditorTag(
                                  label:
                                      '${item['source'] ?? '--'} -> ${item['target'] ?? '--'}(${item['readOnly'] == true ? 'docker_read_only'.tr : 'docker_read_write'.tr})',
                                  caption: '',
                                  onTap: () async {
                                    final updated =
                                        await _showVolumeBindingEditorDialog(
                                          dialogContext,
                                          initialValue: item,
                                        );
                                    if (updated == null) return;
                                    setState(() {
                                      volumeItems[index] = updated;
                                    });
                                  },
                                  onDelete: () {
                                    setState(() {
                                      volumeItems.removeAt(index);
                                    });
                                  },
                                );
                              })
                              .toList(growable: false),
                          addLabel: '${'add'.tr} ${'docker_mounts'.tr}',
                          onAdd: () async {
                            final created =
                                await _showVolumeBindingEditorDialog(
                                  dialogContext,
                                );
                            if (created == null) return;
                            setState(() {
                              volumeItems.add(created);
                            });
                          },
                        ),
                      ],
                    ),
                    if (advancedMode) ...[
                      const SizedBox(height: 16),
                      Text(
                        'docker_advanced_mode'.tr,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'docker_advanced_mode_hint'.tr,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: commandCtrl,
                        decoration: InputDecoration(
                          labelText: 'docker_container_command'.tr,
                          hintText: 'docker_container_command_hint'.tr,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: cpuCtrl,
                              decoration: InputDecoration(
                                labelText: 'docker_cpu_limit'.tr,
                                hintText: 'docker_cpu_limit_hint'.tr,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: memoryCtrl,
                              decoration: InputDecoration(
                                labelText: 'docker_memory_limit'.tr,
                                hintText: 'docker_memory_limit_hint'.tr,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _CreateListSection(
                        title: 'docker_env_vars'.tr,
                        subtitle: 'docker_env_vars_section_hint'.tr,
                        emptyText: '',
                        addButtonText: '',
                        onAdd: () {},
                        headerTrailing: const SizedBox.shrink(),
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                        children: [
                          _CreateTagGrid(
                            items: envItems
                                .asMap()
                                .entries
                                .map((entry) {
                                  final index = entry.key;
                                  final item = entry.value;
                                  final key = item['key']?.toString() ?? '--';
                                  final value = item['value']?.toString() ?? '';
                                  return _CreateEditorTag(
                                    label: '$key=$value',
                                    caption: '',
                                    onTap: () async {
                                      final updated =
                                          await _showEnvVarEditorDialog(
                                            dialogContext,
                                            initialValue: item,
                                          );
                                      if (updated == null) return;
                                      setState(() {
                                        envItems[index] = updated;
                                      });
                                    },
                                    onDelete: () {
                                      setState(() {
                                        envItems.removeAt(index);
                                      });
                                    },
                                  );
                                })
                                .toList(growable: false),
                            addLabel: '${'add'.tr} ${'docker_env_vars'.tr}',
                            onAdd: () async {
                              final created = await _showEnvVarEditorDialog(
                                dialogContext,
                              );
                              if (created == null) return;
                              setState(() {
                                envItems.add(created);
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () async {
                  final chosenImage = imageOptions.firstWhereOrNull(
                    (item) => item['id']?.toString() == selectedImageId,
                  );
                  if (chosenImage == null) {
                    ToastUtil.show('docker_image_name_required'.tr);
                    return;
                  }
                  final body = {
                    'image': chosenImage['repository']?.toString() ?? '',
                    'tag': chosenImage['tag']?.toString() ?? '',
                    'name': nameCtrl.text.trim(),
                    'command': commandCtrl.text.trim(),
                    'restartPolicy': restartPolicy,
                    'env': envItems,
                    'ports': portItems,
                    'volumes': volumeItems,
                    'resources': {
                      'cpus': cpuCtrl.text.trim(),
                      'memory': memoryCtrl.text.trim(),
                    },
                  };
                  final ok = await controller.createContainer(body);
                  if (ok && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: Text('create'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showImportImageDialog(
  BuildContext context,
  DockerController controller,
) async {
  final archiveCtrl = TextEditingController();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text('docker_import_image'.tr),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'docker_import_image_hint'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: archiveCtrl,
                readOnly: true,
                onTap: () async {
                  final picked = await showFolderPickerBottomSheet(
                    dialogContext,
                    multiSelect: false,
                    allowFileSelect: true,
                  );
                  final path = (picked != null && picked.isNotEmpty)
                      ? picked.first.trim()
                      : '';
                  if (!_isDockerImageArchivePath(path)) return;
                  archiveCtrl.text = path;
                },
                decoration: InputDecoration(
                  labelText: 'docker_image_archive'.tr,
                  hintText: 'docker_image_archive_hint'.tr,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () async {
                      final picked = await showFolderPickerBottomSheet(
                        dialogContext,
                        multiSelect: false,
                        allowFileSelect: true,
                      );
                      final path = (picked != null && picked.isNotEmpty)
                          ? picked.first.trim()
                          : '';
                      if (path.isEmpty) return;
                      if (!_isDockerImageArchivePath(path)) {
                        ToastUtil.show('docker_image_archive_invalid'.tr);
                        return;
                      }
                      archiveCtrl.text = path;
                    },
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              final archivePath = archiveCtrl.text.trim();
              if (archivePath.isEmpty) {
                ToastUtil.show('docker_image_archive_required'.tr);
                return;
              }
              if (!_isDockerImageArchivePath(archivePath)) {
                ToastUtil.show('docker_image_archive_invalid'.tr);
                return;
              }
              final ok = await controller.importImage(archivePath: archivePath);
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('docker_start_import'.tr),
          ),
        ],
      );
    },
  );
}

Future<void> _showTagImageDialog(
  BuildContext context,
  DockerController controller,
  Map<String, dynamic> image,
) async {
  final repositoryCtrl = TextEditingController(
    text: image['repository']?.toString() == '<none>'
        ? ''
        : image['repository']?.toString() ?? '',
  );
  final tagCtrl = TextEditingController(
    text: image['tag']?.toString() == '<none>'
        ? 'latest'
        : image['tag']?.toString() ?? 'latest',
  );
  final sourceReference = image['reference']?.toString().trim() ?? '';
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text('docker_change_tag'.tr),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: repositoryCtrl,
                decoration: InputDecoration(
                  labelText: 'docker_image_name'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagCtrl,
                decoration: InputDecoration(
                  labelText: 'docker_tag'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              if (repositoryCtrl.text.trim().isEmpty ||
                  tagCtrl.text.trim().isEmpty) {
                ToastUtil.show('docker_image_tag_required'.tr);
                return;
              }
              final ok = await controller.tagImage(
                imageId: image['id']?.toString() ?? '',
                repository: repositoryCtrl.text.trim(),
                tag: tagCtrl.text.trim(),
                sourceReference: sourceReference,
              );
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('save'.tr),
          ),
        ],
      );
    },
  );
}

Future<void> _showLogsDialog(
  BuildContext context,
  DockerController controller,
  Map<String, dynamic> container,
) async {
  final tailCtrl = TextEditingController(text: '200');
  final scrollCtrl = ScrollController();
  final logs = await controller.fetchContainerLogs(
    containerId: container['id']?.toString() ?? '',
    tail: 200,
  );
  if (logs == null) return;
  final items = logs['items'] is List ? logs['items'] as List : const [];
  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollCtrl.hasClients) return;
      scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
    });
  }

  if (!context.mounted) return;
  scrollToBottom();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          scrollToBottom();
          return DialogUtil.createAlertDialog(
            title: Text('docker_view_logs'.tr),
            content: SizedBox(
              width: 680,
              height: MediaQuery.of(context).size.height * 0.68,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tailCtrl,
                          decoration: InputDecoration(
                            labelText: 'docker_logs_tail'.tr,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () async {
                          final next = await controller.fetchContainerLogs(
                            containerId: container['id']?.toString() ?? '',
                            tail: int.tryParse(tailCtrl.text.trim()) ?? 200,
                          );
                          if (next == null) return;
                          final nextItems = next['items'] is List
                              ? next['items'] as List
                              : const [];
                          items
                            ..clear()
                            ..addAll(nextItems);
                          setState(() {});
                          scrollToBottom();
                        },
                        child: Text('refresh'.tr),
                      ),
                      TextButton(
                        onPressed: () async {
                          final next = await controller.fetchContainerLogs(
                            containerId: container['id']?.toString() ?? '',
                            tail: int.tryParse(tailCtrl.text.trim()) ?? 200,
                            streamOutput: true,
                          );
                          if (next != null && dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        child: Text('docker_follow_logs'.tr),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: items.isEmpty
                          ? Center(child: Text('no_data'.tr))
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final line = items[index] is Map
                                    ? (items[index] as Map)['text']
                                              ?.toString() ??
                                          ''
                                    : items[index].toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: SelectableText(
                                    line,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(fontFamily: 'RobotoMono'),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final text = items
                      .map(
                        (item) => item is Map
                            ? item['text']?.toString() ?? ''
                            : item.toString(),
                      )
                      .join('\n');
                  await Clipboard.setData(ClipboardData(text: text));
                  ToastUtil.show('docker_logs_copied'.tr);
                },
                child: Text('copy'.tr),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('ok'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showConfigEditorDialog(
  BuildContext context,
  DockerController controller,
) async {
  final editorCtrl = TextEditingController(
    text: controller.config['content']?.toString() ?? '{\n}\n',
  );
  final pathText = controller.config['path']?.toString() ?? '--';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text('docker_config_file'.tr),
        content: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KvRow(label: 'docker_config_path'.tr, value: pathText),
              const SizedBox(height: 8),
              Text(
                'docker_config_file_hint'.tr,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editorCtrl,
                maxLines: 20,
                minLines: 16,
                decoration: InputDecoration(
                  labelText: 'docker_config_content'.tr,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                style: Theme.of(
                  dialogContext,
                ).textTheme.bodyMedium?.copyWith(fontFamily: 'RobotoMono'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: controller.dockerServiceOperating.value
                ? null
                : () async {
                    final ok = await controller.toggleDockerService();
                    if (ok && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
            child: Text(
              controller.dockerAvailable.value
                  ? 'docker_stop_service'.tr
                  : 'docker_start_service'.tr,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () async {
              final raw = editorCtrl.text;
              try {
                final parsed = jsonDecode(raw);
                if (parsed is! Map<String, dynamic>) {
                  ToastUtil.show('docker_config_json_object_required'.tr);
                  return;
                }
              } on FormatException catch (error) {
                ToastUtil.show(
                  '${'docker_config_json_invalid'.tr}: ${error.message}',
                );
                return;
              }
              final ok = await controller.saveConfigContent(raw);
              if (ok && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('save'.tr),
          ),
        ],
      );
    },
  );
}

Future<void> _showTaskLogsSheet(
  BuildContext context,
  DockerController controller,
) async {
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.76,
          child: _TaskLogsPanel(controller: controller, showLeftBorder: false),
        );
      },
    );
  } finally {
    controller.setTaskLogsPolling(false);
  }
}

Future<Map<String, dynamic>?> _showEnvVarEditorDialog(
  BuildContext context, {
  Map<String, dynamic>? initialValue,
}) async {
  final keyCtrl = TextEditingController(
    text: initialValue?['key']?.toString() ?? '',
  );
  final valueCtrl = TextEditingController(
    text: initialValue?['value']?.toString() ?? '',
  );
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return DialogUtil.createAlertDialog(
        title: Text(
          initialValue == null
              ? '${'add'.tr} ${'docker_env_vars'.tr}'
              : '${'edit'.tr} ${'docker_env_vars'.tr}',
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: InputDecoration(
                  labelText: 'docker_key'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                decoration: InputDecoration(
                  labelText: 'docker_value'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              if (keyCtrl.text.trim().isEmpty) {
                ToastUtil.show('docker_key_required'.tr);
                return;
              }
              Navigator.of(
                dialogContext,
              ).pop({'key': keyCtrl.text.trim(), 'value': valueCtrl.text});
            },
            child: Text('save'.tr),
          ),
        ],
      );
    },
  );
}

Future<Map<String, dynamic>?> _showPortBindingEditorDialog(
  BuildContext context, {
  Map<String, dynamic>? initialValue,
}) async {
  final hostIpCtrl = TextEditingController(
    text: initialValue?['hostIp']?.toString() ?? '0.0.0.0',
  );
  final hostPortCtrl = TextEditingController(
    text: initialValue?['hostPort']?.toString() ?? '',
  );
  final containerPortCtrl = TextEditingController(
    text: initialValue?['containerPort']?.toString() ?? '',
  );
  var protocol = initialValue?['protocol']?.toString() ?? 'tcp';
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return DialogUtil.createAlertDialog(
            title: Text(
              initialValue == null
                  ? '${'add'.tr} ${'docker_ports'.tr}'
                  : '${'edit'.tr} ${'docker_ports'.tr}',
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: hostIpCtrl,
                    decoration: InputDecoration(
                      labelText: 'docker_host_ip'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hostPortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'docker_host_port'.tr,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: containerPortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'docker_container_port'.tr,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: protocol,
                    decoration: InputDecoration(
                      labelText: 'docker_protocol'.tr,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'tcp',
                        child: Text('TCP'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'udp',
                        child: Text('UDP'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        protocol = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () {
                  final hostPort = int.tryParse(hostPortCtrl.text.trim());
                  final containerPort = int.tryParse(
                    containerPortCtrl.text.trim(),
                  );
                  if (hostPort == null || containerPort == null) {
                    ToastUtil.show('docker_port_invalid'.tr);
                    return;
                  }
                  Navigator.of(dialogContext).pop({
                    'hostIp': hostIpCtrl.text.trim(),
                    'hostPort': hostPort,
                    'containerPort': containerPort,
                    'protocol': protocol,
                  });
                },
                child: Text('save'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<Map<String, dynamic>?> _showVolumeBindingEditorDialog(
  BuildContext context, {
  Map<String, dynamic>? initialValue,
}) async {
  final sourceCtrl = TextEditingController(
    text: initialValue?['source']?.toString() ?? '',
  );
  final targetCtrl = TextEditingController(
    text: initialValue?['target']?.toString() ?? '',
  );
  var readOnly = initialValue?['readOnly'] == true;
  return await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return DialogUtil.createAlertDialog(
            title: Text(
              initialValue == null
                  ? '${'add'.tr} ${'docker_mounts'.tr}'
                  : '${'edit'.tr} ${'docker_mounts'.tr}',
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sourceCtrl,
                    readOnly: true,
                    onTap: () async {
                      final picked = await showFolderPickerBottomSheet(
                        context,
                        multiSelect: false,
                        allowFileSelect: false,
                      );
                      final path = (picked != null && picked.isNotEmpty)
                          ? picked.first.trim()
                          : '';
                      if (path.isEmpty) return;
                      sourceCtrl.text = path;
                    },
                    decoration: InputDecoration(
                      labelText: 'source'.tr,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () async {
                          final picked = await showFolderPickerBottomSheet(
                            context,
                            multiSelect: false,
                            allowFileSelect: false,
                          );
                          final path = (picked != null && picked.isNotEmpty)
                              ? picked.first.trim()
                              : '';
                          if (path.isEmpty) return;
                          sourceCtrl.text = path;
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetCtrl,
                    decoration: InputDecoration(
                      labelText: 'docker_target_path'.tr,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: readOnly,
                    contentPadding: EdgeInsets.zero,
                    title: Text('docker_read_only'.tr),
                    onChanged: (value) {
                      setState(() {
                        readOnly = value == true;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () {
                  if (sourceCtrl.text.trim().isEmpty ||
                      targetCtrl.text.trim().isEmpty) {
                    ToastUtil.show('docker_volume_source_target_required'.tr);
                    return;
                  }
                  Navigator.of(dialogContext).pop({
                    'source': sourceCtrl.text.trim(),
                    'target': targetCtrl.text.trim(),
                    'readOnly': readOnly,
                  });
                },
                child: Text('save'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}

// ============================================================
// Dialog helper widgets
// ============================================================

class _CreateListSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyText;
  final String addButtonText;
  final VoidCallback onAdd;
  final List<Widget> children;
  final Widget? headerTrailing;
  final EdgeInsetsGeometry padding;

  const _CreateListSection({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.addButtonText,
    required this.onAdd,
    required this.children,
    this.headerTrailing,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return CustomGlassCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              headerTrailing ??
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(addButtonText),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          if (children.isEmpty && emptyText.trim().isNotEmpty)
            Text(
              emptyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _CreateItemCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CreateItemCard({
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: onEdit, child: Text('edit'.tr)),
              TextButton(onPressed: onDelete, child: Text('delete'.tr)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateModeToggle extends StatelessWidget {
  final bool advancedMode;
  final ValueChanged<bool> onChanged;

  const _CreateModeToggle({
    required this.advancedMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: _CreateModeOption(
                label: 'docker_basic_mode'.tr,
                icon: Icons.flash_on_outlined,
                selected: !advancedMode,
                onTap: () => onChanged(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CreateModeOption(
                label: 'docker_advanced_mode'.tr,
                icon: Icons.tune_outlined,
                selected: advancedMode,
                onTap: () => onChanged(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateModeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CreateModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? Colors.white
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateTagGrid extends StatelessWidget {
  final List<Widget> items;
  final String addLabel;
  final VoidCallback onAdd;

  const _CreateTagGrid({
    required this.items,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...items,
          _CreateAddTag(label: addLabel, onTap: onAdd),
        ],
      ),
    );
  }
}

class _CreateEditorTag extends StatelessWidget {
  final String label;
  final String caption;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CreateEditorTag({
    required this.label,
    required this.caption,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (caption.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateAddTag extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CreateAddTag({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Dialog helpers
// ============================================================

const List<(String, String)> _restartPolicyOptions = [
  ('no', 'docker_restart_no'),
  ('unless-stopped', 'docker_restart_unless_stopped'),
  ('always', 'docker_restart_always'),
  ('on-failure', 'docker_restart_on_failure'),
];

List<Map<String, String>> _buildCreateContainerImageOptions(
  List<Map<String, dynamic>> images,
) {
  return images
      .map((item) {
        final repository = item['repository']?.toString().trim() ?? '';
        final tag = item['tag']?.toString().trim() ?? '';
        final id = item['id']?.toString().trim() ?? '';
        if (repository.isEmpty ||
            repository == '<none>' ||
            tag.isEmpty ||
            tag == '<none>' ||
            id.isEmpty) {
          return <String, String>{};
        }
        return {
          'id': id,
          'repository': repository,
          'tag': tag,
          'label': '$repository:$tag',
        };
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _isDockerImageArchivePath(String path) {
  final lower = path.trim().toLowerCase();
  return lower.endsWith('.tar') ||
      lower.endsWith('.tar.gz') ||
      lower.endsWith('.tgz');
}
