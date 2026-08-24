part of '../user_management_view.dart';

class _UserManagementLoginRecordsTab extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementLoginRecordsTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final records = ctrl.loginRecords.toList();
      if (records.isEmpty) {
        return const CustomEmptyState();
      }

      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 100) {
            ctrl.loadMoreLoginRecords();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: records.length + 1,
          itemBuilder: (_, i) {
            if (i < records.length) {
              return CustomLoginRecordCard(record: records[i]);
            }

            return Obx(() {
              final loading = ctrl.loginRecordsLoading.value;
              final hasMore = ctrl.loginRecordsHasMore.value;
              if (loading) {
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
              return const SizedBox.shrink();
            });
          },
        ),
      );
    });
  }
}

class _UserManagementOperationLogsTab extends StatefulWidget {
  final UserManagementController ctrl;
  const _UserManagementOperationLogsTab({required this.ctrl});

  @override
  State<_UserManagementOperationLogsTab> createState() =>
      _UserManagementOperationLogsTabState();
}

class _UserManagementOperationLogsTabState
    extends State<_UserManagementOperationLogsTab> {
  TabController? _tabController;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int? _lastUidRequested;

  void _maybeLoad() {
    final tab = _tabController;
    if (tab == null) return;
    if (tab.index != 2) return;

    final ids = widget.ctrl.selectedIds.toList();
    if (ids.isEmpty) return;
    final uid = ids.first;

    if (widget.ctrl.operationLogsLoading.value) return;
    if (widget.ctrl.operationLogs.isNotEmpty) return;
    if (_lastUidRequested == uid) return;
    _lastUidRequested = uid;
    widget.ctrl.refreshOperationLogs(uid);
  }

  void _onTabChanged() {
    widget.ctrl.operationLogsTabActive.value = _tabController?.index == 2;
    _maybeLoad();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        widget.ctrl.loadMoreOperationLogs();
      }
    });

    _searchController.text = widget.ctrl.operationLogsKeyword.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = DefaultTabController.of(context);
    if (!identical(_tabController, tab)) {
      _tabController?.removeListener(_onTabChanged);
      _tabController = tab;
      _tabController?.addListener(_onTabChanged);
      widget.ctrl.operationLogsTabActive.value = _tabController?.index == 2;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController = null;
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      _maybeLoad();

      final logs = widget.ctrl.operationLogs.toList();
      final loading = widget.ctrl.operationLogsLoading.value;
      final theme = Theme.of(context);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        if (widget.ctrl.operationLogsLoading.value) return;
        if (!widget.ctrl.operationLogsHasMore.value) return;
        if (_scrollController.position.maxScrollExtent <= 0) {
          widget.ctrl.loadMoreOperationLogs();
        }
      });

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => widget.ctrl.operationLogsKeyword.value = v,
                decoration: InputDecoration(
                  hintText: 'search'.tr,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                if (logs.isEmpty) {
                  if (loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const CustomEmptyState();
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: logs.length + 1,
                  itemBuilder: (_, i) {
                    if (i < logs.length) {
                      return FileLogItem(log: logs[i], noLeftPadding: true);
                    }

                    return Obx(() {
                      final loading = widget.ctrl.operationLogsLoading.value;
                      final hasMore = widget.ctrl.operationLogsHasMore.value;
                      if (loading) {
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
                      return const SizedBox.shrink();
                    });
                  },
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
