import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../../utils/dialog_util.dart';
import '../../../../utils/file_util.dart';
import '../../../../utils/toast_util.dart';
import '../../list/service/book_local_cache_service_stub.dart'
    if (dart.library.io) '../../list/service/book_local_cache_service_io.dart';

class BookCacheDownloadView extends StatefulWidget {
  const BookCacheDownloadView({super.key});

  @override
  State<BookCacheDownloadView> createState() => _BookCacheDownloadViewState();
}

class _BookCacheDownloadViewState extends State<BookCacheDownloadView> {
  late Future<List<BookCacheEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = BookLocalCacheService.instance.listCacheEntries();
  }

  Future<void> _reload() async {
    setState(() {
      _future = BookLocalCacheService.instance.listCacheEntries();
    });
  }

  Future<void> _deleteOne(BookCacheEntry entry) async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'book_cache_delete_one_confirm'.trParams({
        'fileHash': entry.fileHash,
      }),
      barrierDismissible: false,
    );
    if (ok != true) return;
    final deleted = await BookLocalCacheService.instance.deleteCache(
      fileHash: entry.fileHash,
    );
    if (!mounted) return;
    ToastUtil.show(deleted ? 'delete_success'.tr : 'delete_failed'.tr);
    await _reload();
  }

  Future<void> _deleteAll() async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'book_cache_delete_all_confirm'.tr,
      barrierDismissible: false,
    );
    if (ok != true) return;
    await BookLocalCacheService.instance.clearAllCaches();
    if (!mounted) return;
    ToastUtil.show('operation_success'.tr);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    return Scaffold(
      body: Container(
        color: customColors?.mainContentBgColor,
        child: FutureBuilder<List<BookCacheEntry>>(
          future: _future,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <BookCacheEntry>[];
            final totalSize = items.fold<int>(0, (sum, e) => sum + e.size);
            final showTotalSize = totalSize > 0;

            Widget content;
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty) {
              content = const Center(child: CircularProgressIndicator());
            } else if (items.isEmpty) {
              content = Center(child: Text('book_cache_empty'.tr));
            } else {
              content = RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final e = items[index];
                    final fileName = p.basename(e.filePath);
                    return ListTile(
                      title: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            e.fileHash,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            e.filePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            FileUtil.formatSize(e.size),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'delete'.tr,
                            onPressed: () => _deleteOne(e),
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        'book_cache_download_title'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (showTotalSize) ...[
                        const SizedBox(width: 8),
                        Text(
                          '(${FileUtil.formatSize(totalSize)})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: 'book_cache_delete_all'.tr,
                        onPressed: _deleteAll,
                        icon: Icon(
                          Icons.delete_sweep_outlined,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: CustomGlassCard(
                      padding: const EdgeInsets.all(8),
                      child: content,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
