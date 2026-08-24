part of '../user_management_view.dart';

class _UserManagementPermissionsTab extends StatelessWidget {
  final int uid;
  final UserManagementController ctrl;
  const _UserManagementPermissionsTab({required this.uid, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<UserManagementController>(
      id: 'permissions_$uid',
      builder: (ctrl) {
        if (!ctrl.userPermissions.containsKey(uid)) {
          ctrl.getPermissions(uid);
        }

        final hasPermissions = ctrl.userPermissions.containsKey(uid);
        final initial = hasPermissions
            ? ctrl.userPermissions[uid]!.toList()
            : <Map<String, dynamic>>[];

        return Column(
          children: [
            if (!hasPermissions)
              const Center(child: CircularProgressIndicator()),
            if (hasPermissions)
              Expanded(
                child: CustomPermissionEditor(
                  initial: initial,
                  onSave: (items) async {
                    return await ctrl.setPermissions(uid, items);
                  },
                  onPickDirectory: (onSelected) async {
                    final paths = await showFolderPickerBottomSheet(context);
                    if (paths != null && paths.isNotEmpty) {
                      for (final path in paths) {
                        onSelected(path);
                      }
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
