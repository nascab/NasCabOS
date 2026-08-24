part of '../file_share_server_view.dart';

class _ConfigCard extends StatelessWidget {
  final FileShareServerController ctrl;
  final String serverType;
  final Map<String, dynamic> item;
  const _ConfigCard({
    required this.ctrl,
    required this.serverType,
    required this.item,
  });

  List<Map<String, dynamic>> _normalizeRootPath(dynamic v) {
    if (v is List) {
      final out = <Map<String, dynamic>>[];
      for (final it in v) {
        if (it is String) {
          final p = it.trim();
          if (p.isNotEmpty) {
            out.add({'path': p, 'write': 1, 'update': 1, 'delete': 1});
          }
          continue;
        }
        if (it is Map) {
          final p = it['path']?.toString().trim() ?? '';
          if (p.isNotEmpty) {
            out.add({
              'path': p,
              'write': it['write'],
              'update': it['update'],
              'delete': it['delete'],
            });
          }
          continue;
        }
      }
      return out;
    }
    if (v is String) {
      final p = v.trim();
      if (p.isEmpty) return const [];
      return [
        {'path': p, 'write': 1, 'update': 1, 'delete': 1},
      ];
    }
    return const [];
  }

  bool _toBool(dynamic v, {bool defaultValue = true}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      if (t == '1' || t == 'true') return true;
      if (t == '0' || t == 'false') return false;
      return defaultValue;
    }
    return defaultValue;
  }

  String _permLabel(Map<String, dynamic> it) {
    final write = _toBool(it['write'], defaultValue: true);
    final update = _toBool(it['update'], defaultValue: true);
    final del = _toBool(it['delete'], defaultValue: true);
    final list = <String>['file_share_server_perm_read'.tr];
    if (write) list.add('file_share_server_perm_write'.tr);
    if (update) list.add('file_share_server_perm_update'.tr);
    if (del) list.add('file_share_server_perm_delete'.tr);
    return '[${list.join('/')}]';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = int.tryParse(item['uid']?.toString() ?? '');
    final username = ctrl.usernameForUid(uid);
    final rootPath = _normalizeRootPath(item['root_path']);

    final title = Text(
      username.isEmpty ? (uid?.toString() ?? '') : username,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall,
    );

    final tagTextStyle = theme.textTheme.bodySmall;
    final tagBorderColor = theme.dividerColor;
    final tagBgColor = theme.colorScheme.surface;

    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      IconButton(
                        tooltip: 'edit'.tr,
                        onPressed: () async {
                          final res = await showDialog<_ConfigDialogResult>(
                            context: context,
                            builder: (_) => _ConfigDialog(
                              ctrl: ctrl,
                              serverType: serverType,
                              existingUids:
                                  ctrl.configsByType[serverType]
                                      ?.map((e) => e['uid'])
                                      .toList() ??
                                  const [],
                              initialItem: item,
                            ),
                          );
                          if (res == null) return;
                          await ctrl.upsertConfig(
                            uid: res.uid,
                            serverType: serverType,
                            rootPath: res.rootPath,
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'delete'.tr,
                        onPressed: () async {
                          final ok = await DialogUtil.showConfirmDialog(
                            title: 'confirm'.tr,
                            content: 'file_share_server_delete_confirm'.tr,
                          );
                          if (ok != true) return;
                          if (uid == null) return;
                          await ctrl.deleteConfig(
                            uid: uid,
                            serverType: serverType,
                          );
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (rootPath.isEmpty)
                    Text(
                      'file_share_server_no_path_selected'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: rootPath
                          .take(12)
                          .map(
                            (it) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: tagBgColor,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: tagBorderColor),
                              ),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 340,
                                ),
                                child: Text(
                                  '${it['path']?.toString() ?? ''} ${_permLabel(it)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tagTextStyle,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
