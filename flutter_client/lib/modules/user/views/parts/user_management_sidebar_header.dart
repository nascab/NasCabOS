part of '../user_management_view.dart';

class _UserManagementSidebarHeader extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementSidebarHeader({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CustomExpandableSearchBar(
                hintText: 'user_mgmt_search'.tr,
                onChanged: (v) => ctrl.keyword.value = v,
                autoSearchOnChange: true,
                onDebouncedChanged: (_) => ctrl.fetchUsers(),
                defaultExpanded: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DimensUtil.containerCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(DimensUtil.containerCardRadius),
            onTap: () => _showUserFormDialog(context, ctrl),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  _CreateUserLabel(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateUserLabel extends StatelessWidget {
  const _CreateUserLabel();

  @override
  Widget build(BuildContext context) {
    return Text('create'.tr);
  }
}

Future<void> _showUserFormDialog(
  BuildContext context,
  UserManagementController ctrl,
) async {
  await showDialog<bool>(
    context: context,
    builder: (_) => CustomUserFormDialog(
      onCreate: (u, p, {userRemark, phone}) =>
          ctrl.createUser(u, p, userRemark: userRemark, phone: phone),
      onUpdate: (id, {username, password, userRemark, phone}) =>
          ctrl.updateUser(
            id,
            username: username,
            password: password,
            userRemark: userRemark,
            phone: phone,
          ),
    ),
  );
}
