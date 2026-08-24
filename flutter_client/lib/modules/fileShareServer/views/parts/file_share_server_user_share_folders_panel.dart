part of '../file_share_server_view.dart';

class _UserShareFoldersPanel extends StatelessWidget {
  final FileShareServerController ctrl;

  const _UserShareFoldersPanel({required this.ctrl});

  String _basename(String p) {
    final s = p.trim();
    if (s.isEmpty) return '';
    final parts = s
        .split(RegExp(r'[\\/]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? s : parts.last;
  }

  Future<void> _addFolder(BuildContext context) async {
    final picked = await showFolderPickerBottomSheet(
      context,
      multiSelect: false,
      allowFileSelect: false,
    );
    final p = (picked != null && picked.isNotEmpty) ? picked.first.trim() : '';
    if (p.isEmpty) return;

    final nameCtrl = TextEditingController(text: _basename(p));
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('user_share_folders_add_title'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'name'.tr,
                hintText: 'user_share_folders_name_hint'.tr,
              ),
            ),
            const SizedBox(height: 12),
            Text(p, style: Get.textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('ok'.tr),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ctrl.addUserShareFolder(path: p, name: nameCtrl.text.trim());
  }

  Future<void> _removeFolder(String p) async {
    final confirm = await DialogUtil.showConfirmDialog(
      title: 'delete'.tr,
      content: 'user_share_folders_delete_confirm'.tr,
    );
    if (confirm != true) return;
    await ctrl.removeUserShareFolder(p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final isAdmin = CurrentUserController.instance.isAdmin;

    return Container(
      color: customColors?.mainContentBgColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomGlassCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text('user_share_folders_title'.tr),
                        IconButton(
                          tooltip: 'help'.tr,
                          onPressed: () {
                            DialogUtil.showInfoDialog(
                              title: 'tip'.tr,
                              content: 'user_share_folder_tooltip'.tr,
                            );
                          },
                          icon: const Icon(Icons.help_outline, size: 18),
                        ),
                      ],
                    ),
                  ),
                  CustomButton(
                    text: 'refresh'.tr,
                    onPressed: () => ctrl.refreshUserShareFolders(),
                  ),
                  if (isAdmin) SizedBox(width: 8),
                  CustomButton(
                    text: 'add'.tr,
                    onPressed: () => _addFolder(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() {
                final loading = ctrl.userShareFoldersLoading.value;
                final items = ctrl.userShareFolders;
                if (loading && items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return CustomNoData(text: 'user_share_folders_empty'.tr);
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final item = items[idx];
                    final name = item['name']?.toString() ?? '';
                    final p = item['path']?.toString() ?? '';
                    final exists = item['exists'] == true;
                    final isDirectory = item['isDirectory'] == true;
                    final missing = !exists || !isDirectory;

                    return CustomGlassCard(
                      child: ListTile(
                        leading: missing
                            ? Icon(
                                Icons.warning_amber_outlined,
                                color: theme.colorScheme.error,
                              )
                            : Image.asset(
                                'assets/icons/file/folder_share.png',
                                width: 22,
                                height: 22,
                              ),
                        title: Text(name.isNotEmpty ? name : _basename(p)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              missing
                                  ? '$p\n${'user_share_folders_missing'.tr}'
                                  : p,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'allow_download'.tr,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                CustomSwitch(
                                  value: item['allowDownload'] == true,
                                  onChanged: isAdmin
                                      ? (v) => ctrl.setUserShareAllowDownload(
                                          path: p,
                                          allowDownload: v,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: isAdmin
                            ? IconButton(
                                tooltip: 'delete'.tr,
                                onPressed: () => _removeFolder(p),
                                icon: const Icon(Icons.delete_outline),
                              )
                            : null,
                      ),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
