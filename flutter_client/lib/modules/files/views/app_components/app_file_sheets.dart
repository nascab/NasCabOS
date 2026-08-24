import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../controllers/app_file_controller.dart';

Future<void> showAppFileCreateSheet(
  BuildContext context,
  FileController ctrl,
) async {
  final theme = Theme.of(context);
  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text('folder_upload_file'.tr),
              onTap: () async {
                final currentDir = ctrl.currentPath.value?.trim() ?? '';
                Get.back();
                final supported = await ctrl.ensureUploadSupported();
                if (!supported) return;
                if (currentDir.isEmpty) {
                  Get.toNamed(AppRoutes.appUploadCenter);
                  return;
                }
                Get.toNamed(
                  AppRoutes.appUploadCenter,
                  arguments: {'targetDir': currentDir},
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text('folder_new_dir'.tr),
              onTap: () async {
                Get.back();
                final supported = await ctrl.ensureCreateFolderSupported();
                if (!supported) return;
                final name = await DialogUtil.showInputDialog(
                  title: 'folder_new_dir'.tr,
                  content: 'app_files_enter_folder_name'.tr,
                  confirmText: 'ok'.tr,
                  cancelText: 'cancel'.tr,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'name_cannot_be_empty'.tr;
                    return null;
                  },
                );
                if (name != null && name.isNotEmpty) {
                  await ctrl.createFolder(name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: Text('folder_new_txt'.tr),
              onTap: () async {
                Get.back();
                final supported = await ctrl.ensureCreateFileSupported();
                if (!supported) return;
                final name = await DialogUtil.showInputDialog(
                  title: 'folder_new_txt'.tr,
                  content: 'enter_new_name'.tr,
                  confirmText: 'ok'.tr,
                  cancelText: 'cancel'.tr,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'name_cannot_be_empty'.tr;
                    return null;
                  },
                );
                final raw = name?.trim() ?? '';
                if (raw.isEmpty) return;
                final fileName = raw.toLowerCase().endsWith('.txt')
                    ? raw
                    : '$raw.txt';
                await ctrl.createTextFileAndOpen(name: fileName, type: 'txt');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('folder_new_md'.tr),
              onTap: () async {
                Get.back();
                final supported = await ctrl.ensureCreateFileSupported();
                if (!supported) return;
                final name = await DialogUtil.showInputDialog(
                  title: 'folder_new_md'.tr,
                  content: 'enter_new_name'.tr,
                  confirmText: 'ok'.tr,
                  cancelText: 'cancel'.tr,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'name_cannot_be_empty'.tr;
                    return null;
                  },
                );
                final raw = name?.trim() ?? '';
                if (raw.isEmpty) return;
                final fileName = raw.toLowerCase().endsWith('.md')
                    ? raw
                    : '$raw.md';
                await ctrl.createTextFileAndOpen(name: fileName, type: 'md');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAppFileSortSheet(
  BuildContext context,
  FileController ctrl,
) async {
  final theme = Theme.of(context);
  final options = <Map<String, String>>[
    {'k': 'name_asc', 't': 'folder_picker_sort_name_asc'},
    {'k': 'name_desc', 't': 'folder_picker_sort_name_desc'},
    {'k': 'size_asc', 't': 'folder_picker_sort_size_asc'},
    {'k': 'size_desc', 't': 'folder_picker_sort_size_desc'},
    {'k': 'type_asc', 't': 'folder_picker_sort_type_asc'},
    {'k': 'type_desc', 't': 'folder_picker_sort_type_desc'},
    {'k': 'mtime_asc', 't': 'folder_picker_sort_mtime_asc'},
    {'k': 'mtime_desc', 't': 'folder_picker_sort_mtime_desc'},
  ];
  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Wrap(
          children: [
            for (final op in options)
              Obx(() {
                final selected = ctrl.sortMode.value == op['k'];
                return ListTile(
                  title: Text((op['t'] ?? '').tr),
                  trailing: selected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    ctrl.setSortMode(op['k'] ?? 'name_asc');
                    Get.back();
                  },
                );
              }),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAppFileFilterSheet(
  BuildContext context,
  FileController ctrl,
) async {
  final theme = Theme.of(context);
  final options = _appFileFilterOptions;
  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Wrap(
          children: [
            for (final op in options)
              Obx(() {
                final selected = ctrl.filterType.value == op['k'];
                return ListTile(
                  title: Text((op['t'] ?? '').tr),
                  trailing: selected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    ctrl.setFilterType(op['k'] ?? 'all');
                    Get.back();
                  },
                );
              }),
          ],
        ),
      ),
    ),
  );
}

Future<void> showAppFileSearchOptionsSheet(
  BuildContext context,
  AppFileController ctrl,
) async {
  final theme = Theme.of(context);
  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Obx(
          () => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                _AppFileSheetHandle(theme: theme),
                const SizedBox(height: 8),
                ..._buildSearchScopeTiles(theme, ctrl),
                Divider(height: 1, color: theme.dividerColor),
                ..._buildSearchTypeTiles(theme, ctrl),
                if (CurrentUserController.instance.isAdmin) ...[
                  Divider(height: 1, color: theme.dividerColor),
                  ListTile(
                    leading: const Icon(Icons.settings_suggest_outlined),
                    title: Text('file_index_settings'.tr),
                    onTap: () async {
                      Get.back();
                      await showAppFileIndexSettingsSheet(ctrl);
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    ),
    isScrollControlled: true,
  );
}

Future<void> showAppFileIndexSettingsSheet(
  AppFileController ctrl,
) async {
  final sheetContext = Get.context ?? Get.overlayContext;
  if (sheetContext == null) return;
  final theme = Theme.of(sheetContext);
  final maxHeight = MediaQuery.of(sheetContext).size.height * 0.88;
  await ctrl.loadIndexConfig(showLoading: false);
  final intervalCtrl = TextEditingController(
    text: ctrl.indexIntervalHours.value.toString(),
  );
  final worker = ever<int>(ctrl.indexIntervalHours, (_) {
    final desired = ctrl.indexIntervalHours.value.toString();
    if (intervalCtrl.text == desired) return;
    intervalCtrl.value = intervalCtrl.value.copyWith(
      text: desired,
      selection: TextSelection.collapsed(offset: desired.length),
      composing: TextRange.empty,
    );
  });

  int safeIntervalHours() {
    final raw = intervalCtrl.text.trim();
    final v = int.tryParse(raw);
    if (v == null) return 72;
    if (v < 1) return 1;
    if (v > 24 * 365) return 24 * 365;
    return v;
  }

  try {
    await Get.bottomSheet(
      Container(
        color: theme.colorScheme.surface,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Obx(
            () => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              shrinkWrap: true,
              children: [
                _AppFileSheetHandle(theme: theme),
                const SizedBox(height: 12),
                Text(
                  'file_index_settings'.tr,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('file_index_enable_title'.tr),
                  subtitle: Text('file_index_enable_subtitle'.tr),
                  trailing: Switch(
                    value: ctrl.indexEnabled.value,
                    activeColor: theme.colorScheme.primary,
                    onChanged: ctrl.indexConfigLoading.value ||
                            ctrl.indexConfigSaving.value
                        ? null
                        : (v) async {
                            await ctrl.saveIndexConfig(
                              enabled: v,
                              intervalHours: safeIntervalHours(),
                            );
                          },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: intervalCtrl,
                        enabled: !ctrl.indexConfigLoading.value &&
                            !ctrl.indexConfigSaving.value,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'file_index_interval_label'.tr,
                          hintText: 'file_index_interval_hint'.tr,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: ctrl.indexConfigLoading.value ||
                                ctrl.indexConfigSaving.value
                            ? null
                            : () async {
                                await ctrl.saveIndexConfig(
                                  enabled: ctrl.indexEnabled.value,
                                  intervalHours: safeIntervalHours(),
                                );
                              },
                        child: Text('save'.tr),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: ctrl.indexConfigLoading.value ||
                              ctrl.indexConfigSaving.value
                          ? null
                          : () async {
                              final confirmed =
                                  await DialogUtil.showConfirmDialog(
                                    title: 'need_confirm'.tr,
                                    content: 'file_index_reset_confirm'.tr,
                                    confirmText: 'ok'.tr,
                                    cancelText: 'cancel'.tr,
                                  );
                              if (confirmed != true) return;
                              await ctrl.resetIndex();
                            },
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: Text('file_index_reset'.tr),
                    ),
                    const Spacer(),
                    if (ctrl.indexConfigLoading.value)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  } finally {
    worker.dispose();
    intervalCtrl.dispose();
  }
}

Future<void> showAppFileViewSheet(
  BuildContext context,
  FileController ctrl,
) async {
  final theme = Theme.of(context);
  final options = <Map<String, String>>[
    {'k': 'grid', 't': 'folder_view_grid'},
    {'k': 'large_grid', 't': 'folder_view_large_grid'},
    {'k': 'list', 't': 'folder_view_list'},
  ];
  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Wrap(
          children: [
            for (final op in options)
              Obx(() {
                final selected = ctrl.viewMode.value == op['k'];
                return ListTile(
                  title: Text((op['t'] ?? '').tr),
                  trailing: selected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    ctrl.setViewMode(op['k'] ?? 'grid');
                    Get.back();
                  },
                );
              }),
          ],
        ),
      ),
    ),
  );
}

List<Widget> _buildSearchScopeTiles(
  ThemeData theme,
  AppFileController ctrl,
) {
  Future<void> handleScopeTap(String scope) async {
    final next = scope == 'global'
        ? 'global'
        : scope == 'subtree'
        ? 'subtree'
        : 'current';
    if (ctrl.searchScope.value == next) {
      Get.back();
      return;
    }
    if (next == 'current') {
      ctrl.setSearchScope('current');
      Get.back();
      return;
    }

    await ctrl.loadIndexConfig(showLoading: false);
    if (ctrl.indexEnabled.value) {
      ctrl.setSearchScope(next);
      Get.back();
      return;
    }

    if (CurrentUserController.instance.isAdmin) {
      final go = await DialogUtil.showConfirmDialog(
        title: 'file_global_search_disabled_title'.tr,
        content: 'file_global_search_disabled_content'.tr,
        confirmText: 'file_global_search_disabled_go_view'.tr,
        cancelText: 'cancel'.tr,
      );
      if (go == true) {
        Get.back();
        await showAppFileIndexSettingsSheet(ctrl);
      }
      return;
    }

    ToastUtil.show('file_global_search_disabled_title'.tr);
  }

  Widget tile({
    required String labelKey,
    required String scope,
    bool showLoading = false,
  }) {
    final selected = ctrl.searchScope.value == scope;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(labelKey.tr),
      trailing: showLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          : null,
      onTap: () => handleScopeTap(scope),
    );
  }

  return [
    tile(labelKey: 'file_search_scope_current_dir', scope: 'current'),
    tile(
      labelKey: 'file_search_scope_current_dir_subtree',
      scope: 'subtree',
      showLoading:
          ctrl.globalSearchLoading.value && ctrl.searchScope.value == 'subtree',
    ),
    tile(
      labelKey: 'file_search_scope_global',
      scope: 'global',
      showLoading:
          ctrl.globalSearchLoading.value && ctrl.searchScope.value == 'global',
    ),
  ];
}

List<Widget> _buildSearchTypeTiles(ThemeData theme, FileController ctrl) {
  return _appFileFilterOptions.map((op) {
    final key = op['k'] ?? 'all';
    final title = op['t'] ?? 'all';
    final selected = ctrl.filterType.value == key;
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(title.tr),
      onTap: () {
        ctrl.setFilterType(key);
        Get.back();
      },
    );
  }).toList(growable: false);
}

class _AppFileSheetHandle extends StatelessWidget {
  const _AppFileSheetHandle({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.dividerColor,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

final _appFileFilterOptions = <Map<String, String>>[
  {'k': 'all', 't': 'all'},
  {'k': 'dir', 't': 'dir'},
  {'k': 'document', 't': 'folder_filter_document'},
  {'k': 'video', 't': 'folder_filter_video'},
  {'k': 'audio', 't': 'folder_filter_audio'},
  {'k': 'image', 't': 'folder_filter_image'},
  {'k': 'archive', 't': 'folder_filter_archive'},
  {'k': 'file', 't': 'file'},
];
