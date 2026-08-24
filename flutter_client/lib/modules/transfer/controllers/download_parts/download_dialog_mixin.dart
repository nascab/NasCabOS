part of '../download_controller.dart';

/// 下载对话框 Mixin
/// 负责显示下载确认对话框，计算文件大小统计，以及选择下载路径
mixin DownloadDialogMixin on DownloadStateMixin {
  void _startStatsOverWebSocket(List<String> paths) {
    statsService?.close();
    statsCount.value = 0;
    isCalculatingStats.value = true;
    statsService = FileStatsService();
    statsService!.connect(
      paths: paths,
      onProgress: (stats) {
        statsSize.value = stats.size;
        statsCount.value = stats.count;
      },
      onComplete: (stats) {
        statsSize.value = stats.size;
        statsCount.value = stats.count;
        isCalculatingStats.value = false;
      },
      onError: (err) {
        isCalculatingStats.value = false;
      },
    );
  }

  /// 计算选定路径的文件大小和数量
  void calculateStats(List<String> paths) {
    bool isHttpUrl(String value) {
      final uri = Uri.tryParse(value);
      return uri != null &&
          uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https');
    }

    statsSize.value = 0;
    statsCount.value = paths.length;
    isCalculatingStats.value = false;
    statsService?.close();
    statsService = null;

    if (paths.any(isHttpUrl)) {
      return;
    }

    // 单文件：HTTP 取属性，避免依赖 WebSocket（直连 HTTP 下 WS 方案需与 baseUrl 一致，且切换 P2P 后更稳）
    if (paths.length == 1) {
      final single = paths.first.trim();
      if (single.isEmpty) {
        statsCount.value = 0;
        return;
      }
      statsCount.value = 1;
      isCalculatingStats.value = true;
      api.getPathAttributes(single).then((attrs) {
        if (attrs != null && attrs['isDirectory'] != true) {
          final sz = attrs['size'];
          statsSize.value = sz is num ? sz.toInt() : 0;
          statsCount.value = 1;
          isCalculatingStats.value = false;
          return;
        }
        _startStatsOverWebSocket(paths);
      }).catchError((_) {
        _startStatsOverWebSocket(paths);
      });
      return;
    }

    _startStatsOverWebSocket(paths);
  }

  /// 构建下载确认对话框
  Widget buildDownloadConfirmDialog(List<String> paths) {
    final defaultPathRx = ''.obs;

    // Check cache first
    final cachedPath = CacheManager().getString('last_download_path');
    if (cachedPath != null && cachedPath.isNotEmpty) {
      bool isValid = false;
      try {
        final dir = Directory(cachedPath);
        if (dir.existsSync()) {
          if (Platform.isMacOS) {
            // macOS沙盒权限检查
            final tempFile = File(p.join(cachedPath, '.nascab_perm_check'));
            tempFile.writeAsStringSync('');
            tempFile.deleteSync();
            isValid = true;
          } else {
            isValid = true;
          }
        }
      } catch (e) {
        isValid = false;
      }

      if (isValid) {
        defaultPathRx.value = cachedPath;
      }
    }

    return AlertDialog(
      title: Text('download'.tr),
      content: Obx(() {
        final sizeStr = FileUtil.formatSize(statsSize.value);
        final count = statsCount.value;
        String getDisplayNameForPath(String value) {
          final uri = Uri.tryParse(value);
          if (uri != null &&
              uri.hasScheme &&
              (uri.scheme == 'http' || uri.scheme == 'https')) {
            final qp = uri.queryParameters;
            final qName =
                (qp['fileName'] ?? qp['filename'] ?? qp['name'])?.trim() ?? '';
            if (qName.isNotEmpty) {
              final normalized = qName.replaceAll('\\', '/');
              return p.basename(normalized);
            }
            final seg = uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : '';
            return seg.isNotEmpty ? seg : 'download';
          }
          return p.basename(value);
        }

        final name = paths.length == 1
            ? getDisplayNameForPath(paths.first)
            : 'items_selected'.trParams({'count': paths.length.toString()});

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'file_name'.tr}: $name'),
            const SizedBox(height: 10),
            if (isCalculatingStats.value)
              Text('${'calculating'.tr}...')
            else
              Text('${'total_size'.tr}: $count ($sizeStr)'),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('${'location'.tr}: '),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Get.theme.canvasColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      defaultPathRx.value.isEmpty
                          ? 'select_path_to_save'.tr
                          : defaultPathRx.value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: defaultPathRx.value.isEmpty ? Colors.grey : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final dir = await FilePicker.platform.getDirectoryPath();
                    if (dir != null) {
                      defaultPathRx.value = dir;
                    }
                  },
                  child: Text('select'.tr),
                ),
              ],
            ),
          ],
        );
      }),
      actions: [
        TextButton(
          onPressed: () {
            statsService?.close();
            Get.back();
          },
          child: Text('cancel'.tr),
        ),
        Obx(
          () => ElevatedButton(
            onPressed: defaultPathRx.value.isEmpty
                ? null
                : () {
                    statsService?.close();
                    CacheManager().setString(
                      'last_download_path',
                      defaultPathRx.value,
                    );
                    Get.back(result: defaultPathRx.value);
                  },
            child: Text('confirm'.tr),
          ),
        ),
      ],
    );
  }
}
