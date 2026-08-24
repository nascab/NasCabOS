part of '../user_management_view.dart';

class _AppUserManagementScaffold extends StatelessWidget {
  final UserManagementController ctrl;
  const _AppUserManagementScaffold({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return _AppUserManagementListPage(ctrl: ctrl);
  }
}

class _AppUserManagementListPage extends StatelessWidget {
  final UserManagementController ctrl;
  const _AppUserManagementListPage({required this.ctrl});

  void _openUserDetail(
    BuildContext context,
    int uid,
    Map<String, dynamic> user,
  ) {
    final username = user['username']?.toString() ?? '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _AppUserManagementDetailPage(ctrl: ctrl, username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('user_mgmt_title'.tr),
        actions: [
          IconButton(
            tooltip: 'create'.tr,
            icon: const Icon(Icons.add),
            onPressed: () => _showUserFormDialog(context, ctrl),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            children: [
              CustomExpandableSearchBar(
                hintText: 'user_mgmt_search'.tr,
                onChanged: (v) => ctrl.keyword.value = v,
                autoSearchOnChange: true,
                onDebouncedChanged: (_) => ctrl.fetchUsers(),
                defaultExpanded: true,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  if (ctrl.users.isEmpty) {
                    return const CustomEmptyState();
                  }
                  return _UserManagementUserList(
                    ctrl: ctrl,
                    onUserTap: (uid, user) =>
                        _openUserDetail(context, uid, user),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppUserManagementDetailPage extends StatelessWidget {
  final UserManagementController ctrl;
  final String username;
  const _AppUserManagementDetailPage({
    required this.ctrl,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final title = username.isNotEmpty ? username : 'user_mgmt_title'.tr;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _AppUserManagementDetailPanel(ctrl: ctrl),
        ),
      ),
    );
  }
}

class _AppUserManagementDetailPanel extends StatelessWidget {
  final UserManagementController ctrl;
  const _AppUserManagementDetailPanel({required this.ctrl});

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
