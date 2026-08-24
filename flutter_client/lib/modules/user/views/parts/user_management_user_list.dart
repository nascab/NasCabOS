part of '../user_management_view.dart';

class _UserManagementUserList extends StatelessWidget {
  final UserManagementController ctrl;
  final void Function(int uid, Map<String, dynamic> user)? onUserTap;
  const _UserManagementUserList({required this.ctrl, this.onUserTap});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final users = ctrl.users.toList();
      final loadingMore = ctrl.usersLoadingMore.value;
      final hasMore = ctrl.usersHasMore.value;
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          final isUserScroll =
              n is ScrollUpdateNotification || n is OverscrollNotification;
          if (!isUserScroll) return false;
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 120) {
            ctrl.loadMoreUsers();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: users.length + 1,
          itemBuilder: (_, i) {
            if (i < users.length) {
              final u = users[i];
              final uid = u['id'] as int;
              final selected = ctrl.selectedIds.contains(uid);
              return CustomUserCard(
                user: u,
                selected: selected,
                onTap: () {
                  ctrl.selectedIds
                    ..clear()
                    ..add(uid);
                  ctrl.refreshLoginRecords(uid);
                  onUserTap?.call(uid, u);
                },
                onToggleActive: (val) {
                  ctrl.updateUser(uid, isActive: val);
                },
              );
            }

            if (users.isEmpty) return const SizedBox.shrink();
            if (loadingMore) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!hasMore) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: Text('no_more'.tr)),
              );
            }
            return const SizedBox(height: 48);
          },
        ),
      );
    });
  }
}
