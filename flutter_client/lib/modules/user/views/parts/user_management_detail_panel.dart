part of '../user_management_view.dart';

class _UserManagementDetailPanel extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementDetailPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ids = ctrl.selectedIds.toList();
      if (ids.isEmpty) {
        return const CustomEmptyState();
      }

      final uid = ids.first;
      final user =
          ctrl.users.firstWhereOrNull((e) => e['id'] == uid) ??
          <String, dynamic>{};
      //用户类型
      final type = user['type']?.toString();
      final showPermissionsTab = type != 'super_admin';
      final tabLength = showPermissionsTab ? 4 : 3;
      final tabs = [
        Tab(text: 'user_mgmt_2fa'.tr),
        Tab(text: 'user_mgmt_login_records'.tr),
        Tab(text: 'user_mgmt_operation_logs'.tr),
        if (showPermissionsTab) Tab(text: 'user_mgmt_permissions'.tr),
      ];

      return DefaultTabController(
        length: tabLength,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomUserInfoCard(user: user, ctrl: ctrl),
            const SizedBox(height: 8),
            TabBar(
              tabs: tabs,
              tabAlignment: TabAlignment.start,
              isScrollable: true,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _UserManagementTwofaTab(uid: uid, user: user, ctrl: ctrl),
                  _UserManagementLoginRecordsTab(ctrl: ctrl),
                  _UserManagementOperationLogsTab(ctrl: ctrl),
                  if (showPermissionsTab)
                    _UserManagementPermissionsTab(uid: uid, ctrl: ctrl),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
