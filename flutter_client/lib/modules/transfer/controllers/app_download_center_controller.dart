import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../utils/file_util.dart';
import '../../../utils/toast_util.dart';
import '../models/transfer_task.dart';
import '../storage/download_history_storage.dart';
import 'download_controller.dart';

class DownloadedFileEntry {
  final int id;
  final String path;
  final String name;
  final String remotePath;
  final int size;
  final DateTime completedTime;
  final bool isImage;
  final bool isVideo;
  final bool fileMissing;

  const DownloadedFileEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.remotePath,
    required this.size,
    required this.completedTime,
    required this.isImage,
    required this.isVideo,
    required this.fileMissing,
  });

  String get sizeText => FileUtil.formatSize(size);
  String get mtimeText =>
      DateFormat('yyyy-MM-dd HH:mm').format(completedTime.toLocal());
}

class AppDownloadCenterController extends GetxController {
  AppDownloadCenterController({DownloadController? downloadController})
    : downloadController =
          downloadController ??
          (Get.isRegistered<DownloadController>()
              ? Get.find<DownloadController>()
              : Get.put(DownloadController(), permanent: true));

  final DownloadController downloadController;

  final RxString downloadDirPath = ''.obs;
  final RxList<DownloadedFileEntry> downloadedFiles =
      <DownloadedFileEntry>[].obs;
  final RxBool isRefreshingFiles = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;

  static const int _pageSize = 30;
  int _nextOffset = 0;

  Worker? _tasksWorker;
  Timer? _refreshDebounce;

  @override
  void onInit() {
    super.onInit();
    _initDownloadDir();
    _tasksWorker = ever<List<dynamic>>(downloadController.tasks, (_) {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 600), () {
        loadFirstPage();
      });
    });
  }

  @override
  void onClose() {
    _tasksWorker?.dispose();
    _refreshDebounce?.cancel();
    super.onClose();
  }

  Future<void> _initDownloadDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = p.join(appDir.path, 'NasCabDownload');
      downloadDirPath.value = dir;
      await Directory(dir).create(recursive: true);
    }
    if (!kIsWeb) {
      await loadFirstPage();
    }
  }

  Future<bool> _localPathExists(String path) async {
    final t = path.trim();
    if (t.isEmpty) return false;
    try {
      if (t.startsWith('content://')) {
        return await File(t).exists();
      }
      final f = File(t);
      if (await f.exists()) return true;
      return await FileSystemEntity.isDirectory(t) && await Directory(t).exists();
    } catch (_) {
      return false;
    }
  }

  Future<DownloadedFileEntry> _rowToEntry(DownloadHistoryRow row) async {
    final lower = row.displayName.toLowerCase();
    final exists = await _localPathExists(row.localPath);
    return DownloadedFileEntry(
      id: row.id,
      path: row.localPath,
      name: row.displayName,
      remotePath: row.remotePath,
      size: row.size,
      completedTime: DateTime.fromMillisecondsSinceEpoch(row.completedAtMs),
      isImage: _isImageExt(lower),
      isVideo: _isVideoExt(lower),
      fileMissing: !exists,
    );
  }

  /// 下拉刷新 / 首次进入
  Future<void> loadFirstPage() async {
    if (kIsWeb) return;
    if (isRefreshingFiles.value) return;
    isRefreshingFiles.value = true;
    try {
      _nextOffset = 0;
      hasMore.value = true;
      final rows = await DownloadHistoryStorage.instance.page(
        offset: 0,
        limit: _pageSize,
      );
      final entries = <DownloadedFileEntry>[];
      for (final r in rows) {
        entries.add(await _rowToEntry(r));
      }
      downloadedFiles.assignAll(entries);
      _nextOffset = entries.length;
      hasMore.value = rows.length >= _pageSize;
    } finally {
      isRefreshingFiles.value = false;
    }
  }

  /// 列表滚动到底部时加载更多
  Future<void> loadMore() async {
    if (kIsWeb) return;
    if (!hasMore.value || isLoadingMore.value || isRefreshingFiles.value) {
      return;
    }
    isLoadingMore.value = true;
    try {
      final rows = await DownloadHistoryStorage.instance.page(
        offset: _nextOffset,
        limit: _pageSize,
      );
      if (rows.isEmpty) {
        hasMore.value = false;
        return;
      }
      final entries = <DownloadedFileEntry>[];
      for (final r in rows) {
        entries.add(await _rowToEntry(r));
      }
      downloadedFiles.addAll(entries);
      _nextOffset += entries.length;
      hasMore.value = rows.length >= _pageSize;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// 兼容旧调用（刷新按钮）
  Future<void> refreshDownloadedFiles() => loadFirstPage();

  Future<void> shareFile(
    BuildContext context,
    DownloadedFileEntry entry,
  ) async {
    if (entry.fileMissing) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : (box.localToGlobal(Offset.zero) & box.size);

    final file = File(entry.path);
    if (!await file.exists()) return;
    await Share.shareXFiles([XFile(entry.path)], sharePositionOrigin: origin);
  }

  bool get _isIos => Platform.isIOS;

  Future<String?> _mapToInternalDownloadPathIfPossible(String anyPath) async {
    final t = anyPath.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('content://')) return null;
    final base = downloadDirPath.value.trim();
    if (base.isEmpty) return null;
    try {
      final normalized = p.normalize(t).replaceAll('\\', '/');
      final parts = normalized.split('/').where((e) => e.isNotEmpty).toList();
      final idx = parts.lastIndexOf('NasCabDownload');
      if (idx < 0) return null;
      final suffix = parts.sublist(idx + 1);
      if (suffix.isEmpty) return null;
      return p.normalize(p.join(base, p.joinAll(suffix)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteDownloadedFileInAppStorageOnly(String path) async {
    final t = path.trim();
    if (t.isEmpty) return;
    if (await _isPathUnderAppPrivateStorage(t)) {
      await _deleteLocalFileIfPresent(t);
      return;
    }
    final mapped = await _mapToInternalDownloadPathIfPossible(t);
    if (mapped == null) return;
    if (await _isPathUnderAppPrivateStorage(mapped)) {
      await _deleteLocalFileIfPresent(mapped);
    }
  }

  /// 已完成列表：删除记录（Android 可选同时删文件；iOS 始终删文件+记录）
  Future<void> promptDeleteEntry(DownloadedFileEntry entry) async {
    if (kIsWeb) return;
    if (_isIos) {
      final ok = await Get.dialog<bool>(
        AlertDialog(
          title: Text('confirm_delete'.tr),
          content: Text(entry.name),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text('ok'.tr),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _deleteLocalFileIfPresent(entry.path);
        await DownloadHistoryStorage.instance.deleteById(entry.id);
        downloadedFiles.removeWhere((e) => e.id == entry.id);
      }
      return;
    }

    final deleteFileToo = true.obs;
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('confirm_delete'.tr),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('delete_downloaded_local_file'.tr),
                value: deleteFileToo.value,
                onChanged: (v) => deleteFileToo.value = v ?? false,
              ),
              if (deleteFileToo.value) ...[
                const SizedBox(height: 4),
                Text(
                  'delete_downloaded_local_file_hint'.tr,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (deleteFileToo.value) {
        await _deleteDownloadedFileInAppStorageOnly(entry.path);
      }
      await DownloadHistoryStorage.instance.deleteById(entry.id);
      downloadedFiles.removeWhere((e) => e.id == entry.id);
    }
  }

  Future<void> _deleteLocalFileIfPresent(String path) async {
    final t = path.trim();
    if (t.isEmpty) return;
    try {
      if (t.startsWith('content://')) {
        return;
      }
      final e = FileSystemEntity.typeSync(t);
      if (e == FileSystemEntityType.file) {
        final f = File(t);
        if (await f.exists()) await f.delete();
      } else if (e == FileSystemEntityType.directory) {
        final d = Directory(t);
        if (await d.exists()) await d.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 应用私有目录根路径（Documents / Support / 临时 / 缓存等），用于「清理全部」时判断是否可删本地文件。
  /// 已转移到系统下载、相册等公共位置的路径不在此列，不会被删除。
  Future<List<String>> _privateStorageRootsForClear() async {
    final list = <String>[
      (await getApplicationDocumentsDirectory()).path,
      (await getApplicationSupportDirectory()).path,
      (await getTemporaryDirectory()).path,
      (await getApplicationCacheDirectory()).path,
    ];
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        list.add((await getLibraryDirectory()).path);
      } catch (_) {}
    }
    return list;
  }

  /// 路径是否位于应用沙盒/私有存储内（顶部「清理全部」时仅删除此类文件）。
  Future<bool> _isPathUnderAppPrivateStorage(String path) async {
    final t = path.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('content://')) return false;
    try {
      final normalized = p.normalize(p.absolute(t));
      final roots = await _privateStorageRootsForClear();
      for (final root in roots) {
        final r = p.normalize(p.absolute(root));
        final prefix = r.endsWith(p.separator) ? r : '$r${p.separator}';
        if (normalized == r || normalized.startsWith(prefix)) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 顶部：清理下载记录（Android 可选删文件；iOS 直接删记录+文件）
  Future<void> promptClearAllHistory() async {
    if (kIsWeb) return;
    final hasActive = downloadController.tasks.any(
      (t) =>
          t.type == TransferType.download &&
          (t.status == TransferStatus.uploading ||
              t.status == TransferStatus.pending),
    );
    if (hasActive) {
      ToastUtil.show('download_center_stop_tasks_first'.tr);
      return;
    }

    if (_isIos) {
      final ok = await Get.dialog<bool>(
        AlertDialog(
          title: Text('download_history_clear_title'.tr),
          content: Text('download_history_clear_message_ios'.tr),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text('ok'.tr),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _clearAllRecordsAndFilesIos();
      }
      return;
    }

    final deleteFilesToo = true.obs;
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('download_history_clear_title'.tr),
        content: Obx(
          () => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('download_history_clear_message'.tr),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('delete_downloaded_local_file'.tr),
                value: deleteFilesToo.value,
                onChanged: (v) => deleteFilesToo.value = v ?? false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('ok'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (deleteFilesToo.value) {
        final paths = await DownloadHistoryStorage.instance.allLocalPaths();
        for (final path in paths) {
          if (await _isPathUnderAppPrivateStorage(path)) {
            await _deleteLocalFileIfPresent(path);
          }
        }
      }
      await DownloadHistoryStorage.instance.clearAllRecords();
      downloadedFiles.clear();
      hasMore.value = false;
      _nextOffset = 0;
    }
  }

  /// iOS：清空下载记录库，并仅删除仍位于应用沙盒内的本地文件（不删已保存到系统相册等公共位置的副本）。
  Future<void> _clearAllRecordsAndFilesIos() async {
    final paths = await DownloadHistoryStorage.instance.allLocalPaths();
    for (final path in paths) {
      if (await _isPathUnderAppPrivateStorage(path)) {
        await _deleteLocalFileIfPresent(path);
      }
    }
    await DownloadHistoryStorage.instance.clearAllRecords();
    downloadedFiles.clear();
    hasMore.value = false;
    _nextOffset = 0;
  }

  Future<File?> getVideoThumbFile(DownloadedFileEntry entry) async {
    if (!entry.isVideo || entry.fileMissing) return null;
    final videoFile = File(entry.path);
    if (!await videoFile.exists()) return null;

    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'nascab_download_thumbs'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final key = md5
        .convert(
          utf8.encode(
            '${entry.path}|${entry.completedTime.millisecondsSinceEpoch}',
          ),
        )
        .toString();
    final outPath = p.join(cacheDir.path, '$key.jpg');
    final outFile = File(outPath);
    if (await outFile.exists()) return outFile;

    Uint8List? bytes;
    try {
      bytes = await VideoThumbnail.thumbnailData(
        video: entry.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        quality: 70,
      );
    } catch (_) {
      bytes = null;
    }

    if (bytes == null || bytes.isEmpty) return null;
    await outFile.writeAsBytes(bytes, flush: false);
    return outFile;
  }

  bool _isImageExt(String filenameLower) {
    return filenameLower.endsWith('.jpg') ||
        filenameLower.endsWith('.jpeg') ||
        filenameLower.endsWith('.png') ||
        filenameLower.endsWith('.webp') ||
        filenameLower.endsWith('.gif') ||
        filenameLower.endsWith('.bmp') ||
        filenameLower.endsWith('.heic') ||
        filenameLower.endsWith('.heif');
  }

  bool _isVideoExt(String filenameLower) {
    return filenameLower.endsWith('.mp4') ||
        filenameLower.endsWith('.mov') ||
        filenameLower.endsWith('.m4v') ||
        filenameLower.endsWith('.mkv') ||
        filenameLower.endsWith('.webm') ||
        filenameLower.endsWith('.avi') ||
        filenameLower.endsWith('.flv') ||
        filenameLower.endsWith('.ts');
  }
}
