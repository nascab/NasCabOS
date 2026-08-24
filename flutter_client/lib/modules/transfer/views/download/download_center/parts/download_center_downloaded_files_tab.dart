part of '../app_download_center_view.dart';

class _DownloadCenterDownloadedFilesTab extends StatefulWidget {
  const _DownloadCenterDownloadedFilesTab();

  @override
  State<_DownloadCenterDownloadedFilesTab> createState() =>
      _DownloadCenterDownloadedFilesTabState();
}

class _DownloadCenterDownloadedFilesTabState
    extends State<_DownloadCenterDownloadedFilesTab> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final controller = Get.find<AppDownloadCenterController>();
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      controller.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppDownloadCenterController>();
    final theme = Theme.of(context);

    return Obx(() {
      final dir = controller.downloadDirPath.value.trim();
      final files = controller.downloadedFiles;
      final loadingMore = controller.isLoadingMore.value;
      final extra = loadingMore && files.isNotEmpty ? 1 : 0;

      final dirCaption = Platform.isIOS
          ? 'download_center_completed_dir_ios'.tr
          : '${'download_to'.tr} $dir';

      return Column(
        children: [
          if (dir.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: theme.colorScheme.surface,
              child: Text(
                dirCaption,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.loadFirstPage,
              child: files.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        CustomNoData(text: 'task_empty'.tr),
                      ],
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: files.length + extra,
                      separatorBuilder: (_, _) =>
                          const CustomDivider(height: 10),
                      itemBuilder: (context, index) {
                        if (index < files.length) {
                          return _DownloadCenterDownloadedFileItem(
                            entry: files[index],
                          );
                        }
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      );
    });
  }
}
