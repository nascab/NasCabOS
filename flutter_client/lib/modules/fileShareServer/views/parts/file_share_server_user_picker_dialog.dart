part of '../file_share_server_view.dart';

class _UserPickerDialog extends StatelessWidget {
  final FileShareServerController ctrl;
  final int? selectedUid;

  const _UserPickerDialog({required this.ctrl, required this.selectedUid});

  @override
  Widget build(BuildContext context) {
    return DialogUtil.createAlertDialog(
      title: Text('file_share_server_choose_user'.tr),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Obx(() {
          final users = ctrl.usersById.values.toList();
          users.sort((a, b) {
            final au = a['username']?.toString() ?? '';
            final bu = b['username']?.toString() ?? '';
            return au.compareTo(bu);
          });
          if (users.isEmpty) {
            return CustomNoData(text: 'no_data'.tr);
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final u = users[i];
              final uid = int.tryParse(u['id']?.toString() ?? '');
              final selected = uid != null && uid == selectedUid;
              return CustomUserCard(
                user: u,
                selected: selected,
                onTap: () => Navigator.of(context).pop(uid),
                onToggleActive: (_) {},
              );
            },
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
      ],
    );
  }
}
