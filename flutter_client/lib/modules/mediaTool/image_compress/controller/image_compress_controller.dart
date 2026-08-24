import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart' as dio;
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../../../core/api/api_controller.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../../transfer/utils/mobile_media_file_picker.dart';
import '../../../base/components/mobile_upload_source_picker.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../../utils/file_util.dart';
import '../../../../../utils/cache_manager.dart';
import '../service/image_compress_api_service.dart';

class ImageCompressItem {
  final String fileName;
  final int inputSize;
  final int outputSize;
  final String outputFormat;
  final String outputFullPath;
  final int? uploadStartTime;

  ImageCompressItem({
    required this.fileName,
    required this.inputSize,
    required this.outputSize,
    required this.outputFormat,
    required this.outputFullPath,
    required this.uploadStartTime,
  });

  String get inputSizeText => FileUtil.formatSize(inputSize);
  String get outputSizeText => FileUtil.formatSize(outputSize);
  int get savedBytes => max(0, inputSize - outputSize);
  int get savedPercent {
    if (inputSize <= 0) return 0;
    return ((savedBytes / inputSize) * 100).round();
  }
}

class MediaToolImageCompressWebFileBytes {
  final String name;
  final List<int> bytes;

  MediaToolImageCompressWebFileBytes({required this.name, required this.bytes});
}

class ImageCompressController extends GetxController {
  final ImageCompressApiService _api = ImageCompressApiService();
  final CacheManager _cache = CacheManager();

  static const Set<String> _supportedImageExtsWithDot = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.tif',
    '.tiff',
    '.heic',
    '.heif',
  };

  static const List<String> _supportedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'tif',
    'tiff',
    'heic',
    'heif',
  ];

  final RxString quality = 'auto'.obs;
  final RxString format = 'auto'.obs;
  final RxString size = 'auto'.obs;
  final RxnInt customOutSize = RxnInt();
  final RxBool withMeta = true.obs;

  final RxBool busy = false.obs;
  final RxBool dragHover = false.obs;
  final RxList<ImageCompressItem> results = <ImageCompressItem>[].obs;
  final RxnInt lastUploadStartTime = RxnInt();

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    _setupSettingsListeners();
  }

  void _loadSettings() {
    final cachedQuality = _cache.getString(CacheKeys.imageCompressQuality);
    if (cachedQuality != null) {
      quality.value = cachedQuality;
    }

    final cachedFormat = _cache.getString(CacheKeys.imageCompressFormat);
    if (cachedFormat != null) {
      format.value = cachedFormat;
    }

    final cachedSize = _cache.getString(CacheKeys.imageCompressSize);
    if (cachedSize != null) {
      size.value = cachedSize;
    }

    final cachedCustomOutSize = _cache.getInt(
      CacheKeys.imageCompressCustomOutSize,
    );
    if (cachedCustomOutSize != null) {
      customOutSize.value = cachedCustomOutSize;
    }

    final cachedWithMeta = _cache.getBool(CacheKeys.imageCompressWithMeta);
    if (cachedWithMeta != null) {
      withMeta.value = cachedWithMeta;
    }
  }

  void _setupSettingsListeners() {
    ever(
      quality,
      (value) => _cache.setString(CacheKeys.imageCompressQuality, value),
    );
    ever(
      format,
      (value) => _cache.setString(CacheKeys.imageCompressFormat, value),
    );
    ever(size, (value) => _cache.setString(CacheKeys.imageCompressSize, value));
    ever(customOutSize, (value) {
      if (value != null) {
        _cache.setInt(CacheKeys.imageCompressCustomOutSize, value);
      } else {
        _cache.remove(CacheKeys.imageCompressCustomOutSize);
      }
    });
    ever(
      withMeta,
      (value) => _cache.setBool(CacheKeys.imageCompressWithMeta, value),
    );
  }

  Map<String, dynamic> _buildQuery({
    required String fileName,
    required int uploadStartTime,
  }) {
    int? outSize;
    if (size.value == 'custom') {
      outSize = customOutSize.value;
    } else if (size.value != 'auto') {
      outSize = int.tryParse(size.value);
    }

    return {
      'fileName': fileName,
      'uploadStartTime': uploadStartTime,
      'withMeta': withMeta.value ? 1 : 0,
      if (quality.value != 'auto') 'zipQuality': int.tryParse(quality.value),
      if (outSize != null) 'outSize': outSize,
      if (format.value != 'auto') 'zipFormat': format.value,
    };
  }

  int get optimizedCount => results.where((e) => e.savedBytes > 0).length;

  int get optimizedSavedBytesTotal =>
      results.fold<int>(0, (sum, e) => sum + e.savedBytes);

  String get optimizedSavedBytesText =>
      FileUtil.formatSize(optimizedSavedBytesTotal);

  int get optimizedOutputBytesTotal => results
      .where((e) => e.savedBytes > 0)
      .fold<int>(0, (sum, e) => sum + e.outputSize);

  String get optimizedOutputBytesText =>
      FileUtil.formatSize(optimizedOutputBytesTotal);

  int? get zipMinTimeStamp {
    if (results.isEmpty) return null;
    int? minTs;
    for (final it in results) {
      final ts = it.uploadStartTime;
      if (ts == null) continue;
      minTs = (minTs == null) ? ts : min(minTs, ts);
    }
    return minTs ?? lastUploadStartTime.value;
  }

  String _buildDownloadUrl({
    required String apiPath,
    required Map<String, String> query,
  }) {
    final api = ApiController.instance;
    final token = api.accessToken;
    final uri = Uri.parse('${api.baseUrl}$apiPath').replace(
      queryParameters: {...query, if (token != null) 'accessToken': token},
    );
    return uri.toString();
  }

  Future<void> _downloadViaCenter(List<String> urls) async {
    if (urls.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(urls);
  }

  Future<void> pickAndUploadImages() async {
    if (busy.value) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    lastUploadStartTime.value = now;

    try {
      busy.value = true;
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: _supportedImageExtensions,
        withData: kIsWeb,
      );
      if (res == null || res.files.isEmpty) return;

      final supported = <PlatformFile>[];
      var hasUnsupported = false;
      for (final f in res.files) {
        if (_isSupportedImagePath(f.name)) {
          supported.add(f);
        } else {
          hasUnsupported = true;
        }
      }
      if (supported.isEmpty) {
        if (hasUnsupported) {
          ToastUtil.show('file_format_not_supported'.tr);
        }
        return;
      }
      if (hasUnsupported) {
        ToastUtil.show('file_format_not_supported'.tr);
      }

      for (final f in supported) {
        await _uploadOnePlatformFile(f, uploadStartTime: now);
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    } finally {
      busy.value = false;
    }
  }

  Future<void> pickAndUploadByMobileSource(BuildContext context) async {
    if (busy.value) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      await pickAndUploadImages();
      return;
    }

    final source = await showMobileUploadSourcePicker(context);
    if (source == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    lastUploadStartTime.value = now;

    try {
      busy.value = true;
      if (source == MobileUploadSourceType.media) {
        final entries = await MobileMediaFilePicker.pickMediaUploadEntries(
          context,
          includeLivePhotoVideo: false,
        );
        var hasUnsupported = false;
        for (final it in entries) {
          final file = it['file'];
          if (file is! XFile) continue;
          final path = file.path.trim();
          if (path.isEmpty) continue;
          if (!_isSupportedImagePath(path)) {
            hasUnsupported = true;
            continue;
          }
          await _uploadOnePath(path, uploadStartTime: now);
        }
        if (hasUnsupported) {
          ToastUtil.show('file_format_not_supported'.tr);
        }
        return;
      }

      final picked = await MobileMediaFilePicker.pickFiles();
      if (picked.isEmpty) return;
      final supported = <PlatformFile>[];
      var hasUnsupported = false;
      for (final f in picked) {
        if (_isSupportedImagePath(f.name)) {
          supported.add(f);
        } else {
          hasUnsupported = true;
        }
      }
      if (supported.isEmpty) {
        if (hasUnsupported) {
          ToastUtil.show('file_format_not_supported'.tr);
        }
        return;
      }
      if (hasUnsupported) {
        ToastUtil.show('file_format_not_supported'.tr);
      }
      for (final f in supported) {
        await _uploadOnePlatformFile(f, uploadStartTime: now);
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    } finally {
      busy.value = false;
    }
  }

  Future<void> pickAndUploadFolder() async {
    if (busy.value) return;
    if (kIsWeb) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.isEmpty) return;

    final files = await _collectImageFiles(dirPath);
    if (files.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    lastUploadStartTime.value = now;

    try {
      busy.value = true;
      for (final filePath in files) {
        await _uploadOnePath(filePath, uploadStartTime: now);
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    } finally {
      busy.value = false;
    }
  }

  Future<List<String>> _collectImageFiles(String dirPath) async {
    final out = <String>[];
    try {
      await for (final entity in Directory(
        dirPath,
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_supportedImageExtsWithDot.contains(ext)) continue;
        out.add(entity.path);
      }
    } catch (_) {}
    out.sort();
    return out;
  }

  bool _isSupportedImagePath(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return _supportedImageExtsWithDot.contains(ext);
  }

  Future<void> uploadDroppedFiles(List<XFile> files) async {
    if (busy.value) return;
    if (files.isEmpty) return;
    if (kIsWeb) return;

    final paths = <String>[];
    var hasUnsupported = false;
    for (final f in files) {
      final fp = f.path;
      if (fp.isEmpty) continue;
      try {
        if (await FileSystemEntity.isDirectory(fp)) {
          final nested = await _collectImageFiles(fp);
          paths.addAll(nested);
        } else {
          if (_isSupportedImagePath(fp)) {
            paths.add(fp);
          } else {
            hasUnsupported = true;
          }
        }
      } catch (_) {}
    }
    if (paths.isEmpty) {
      if (hasUnsupported) {
        ToastUtil.show('file_format_not_supported'.tr);
      }
      return;
    }
    if (hasUnsupported) {
      ToastUtil.show('file_format_not_supported'.tr);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    lastUploadStartTime.value = now;

    try {
      busy.value = true;
      for (final filePath in paths) {
        await _uploadOnePath(filePath, uploadStartTime: now);
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    } finally {
      busy.value = false;
    }
  }

  Future<void> uploadDroppedWebBytes(
    List<MediaToolImageCompressWebFileBytes> files,
  ) async {
    if (busy.value) return;
    if (!kIsWeb) return;
    if (files.isEmpty) return;

    final supported = <MediaToolImageCompressWebFileBytes>[];
    var hasUnsupported = false;
    for (final f in files) {
      if (_isSupportedImagePath(f.name)) {
        supported.add(f);
      } else {
        hasUnsupported = true;
      }
    }
    if (supported.isEmpty) {
      if (hasUnsupported) {
        ToastUtil.show('file_format_not_supported'.tr);
      }
      return;
    }
    if (hasUnsupported) {
      ToastUtil.show('file_format_not_supported'.tr);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    lastUploadStartTime.value = now;

    try {
      busy.value = true;
      for (final f in supported) {
        await _uploadOneBytes(f.name, f.bytes, uploadStartTime: now);
      }
    } catch (e) {
      ToastUtil.show(e.toString());
    } finally {
      busy.value = false;
    }
  }

  Future<void> _uploadOnePlatformFile(
    PlatformFile f, {
    required int uploadStartTime,
  }) async {
    final name = f.name;
    dio.MultipartFile multipart;
    if (kIsWeb) {
      final bytes = f.bytes;
      if (bytes == null) return;
      multipart = dio.MultipartFile.fromBytes(bytes, filename: name);
    } else {
      final filePath = f.path;
      if (filePath == null) return;
      multipart = await dio.MultipartFile.fromFile(filePath, filename: name);
    }

    final apiRes = await _api.uploadAndCompress(
      file: multipart,
      query: _buildQuery(fileName: name, uploadStartTime: uploadStartTime),
    );
    if (!apiRes.success) {
      ToastUtil.show(apiRes.message ?? 'server_error'.tr);
      return;
    }

    final data = apiRes.data ?? {};
    final outputPath = data['outputFullPath']?.toString() ?? '';
    if (outputPath.isEmpty) return;
    results.insert(
      0,
      ImageCompressItem(
        fileName: name,
        inputSize: (data['inputSize'] is num)
            ? (data['inputSize'] as num).toInt()
            : 0,
        outputSize: (data['outputSize'] is num)
            ? (data['outputSize'] as num).toInt()
            : 0,
        outputFormat: data['outputFormat']?.toString() ?? '',
        outputFullPath: outputPath,
        uploadStartTime: (data['uploadStartTime'] is num)
            ? (data['uploadStartTime'] as num).toInt()
            : uploadStartTime,
      ),
    );
  }

  Future<void> _uploadOneBytes(
    String fileName,
    List<int> bytes, {
    required int uploadStartTime,
  }) async {
    final multipart = dio.MultipartFile.fromBytes(bytes, filename: fileName);

    final apiRes = await _api.uploadAndCompress(
      file: multipart,
      query: _buildQuery(fileName: fileName, uploadStartTime: uploadStartTime),
    );
    if (!apiRes.success) {
      ToastUtil.show(apiRes.message ?? 'server_error'.tr);
      return;
    }

    final data = apiRes.data ?? {};
    final outputPath = data['outputFullPath']?.toString() ?? '';
    if (outputPath.isEmpty) return;
    results.insert(
      0,
      ImageCompressItem(
        fileName: fileName,
        inputSize: (data['inputSize'] is num)
            ? (data['inputSize'] as num).toInt()
            : bytes.length,
        outputSize: (data['outputSize'] is num)
            ? (data['outputSize'] as num).toInt()
            : 0,
        outputFormat: data['outputFormat']?.toString() ?? '',
        outputFullPath: outputPath,
        uploadStartTime: (data['uploadStartTime'] is num)
            ? (data['uploadStartTime'] as num).toInt()
            : uploadStartTime,
      ),
    );
  }

  Future<void> _uploadOnePath(
    String filePath, {
    required int uploadStartTime,
  }) async {
    final name = p.basename(filePath);
    final multipart = await dio.MultipartFile.fromFile(
      filePath,
      filename: name,
    );

    final apiRes = await _api.uploadAndCompress(
      file: multipart,
      query: _buildQuery(fileName: name, uploadStartTime: uploadStartTime),
    );
    if (!apiRes.success) {
      ToastUtil.show(apiRes.message ?? 'server_error'.tr);
      return;
    }

    final data = apiRes.data ?? {};
    final outputPath = data['outputFullPath']?.toString() ?? '';
    if (outputPath.isEmpty) return;
    results.insert(
      0,
      ImageCompressItem(
        fileName: name,
        inputSize: (data['inputSize'] is num)
            ? (data['inputSize'] as num).toInt()
            : 0,
        outputSize: (data['outputSize'] is num)
            ? (data['outputSize'] as num).toInt()
            : 0,
        outputFormat: data['outputFormat']?.toString() ?? '',
        outputFullPath: outputPath,
        uploadStartTime: (data['uploadStartTime'] is num)
            ? (data['uploadStartTime'] as num).toInt()
            : uploadStartTime,
      ),
    );
  }

  void clearResults() {
    results.clear();
    lastUploadStartTime.value = null;
  }

  Future<void> saveFile(ImageCompressItem item) async {
    final suggested =
        '${p.basenameWithoutExtension(item.fileName)}.${item.outputFormat}';
    final url = _buildDownloadUrl(
      apiPath: '/api/mediaTool/imageCompress/file',
      query: {'path': item.outputFullPath, 'fileName': suggested},
    );
    await _downloadViaCenter([url]);
  }

  Future<void> downloadZip() async {
    final ts = zipMinTimeStamp;
    if (ts == null) return;
    final url = _buildDownloadUrl(
      apiPath: '/api/mediaTool/imageCompress/zip',
      query: {'minTimeStamp': ts.toString(), 'fileName': 'all-image.zip'},
    );
    await _downloadViaCenter([url]);
  }
}
