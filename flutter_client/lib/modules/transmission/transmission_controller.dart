import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/api/base_api_service.dart';
import '../../../utils/cache_manager.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/server_version_util.dart';
import '../../../utils/toast_util.dart';
import '../files/service/file_api_service.dart';
import 'service/transmission_api_service.dart';

class TransmissionController extends GetxController {
  static const int _requiredServerVersion = 9;
  static const String _lastDownloadDirKeyPrefix = 'transmission_last_download_dir';
  final _api = TransmissionApiService.instance;

  final RxString currentTab = 'overview'.obs;
  final RxMap<String, dynamic> status = <String, dynamic>{}.obs;
  final RxMap<String, dynamic> config = <String, dynamic>{}.obs;
  final RxMap<String, dynamic> session = <String, dynamic>{}.obs;
  final RxMap<String, dynamic> sessionStats = <String, dynamic>{}.obs;
  final RxList<Map<String, dynamic>> torrents = <Map<String, dynamic>>[].obs;

  final RxBool serviceOperating = false.obs;
  final RxBool loadingTorrents = false.obs;
  final RxBool savingConfig = false.obs;
  final RxString torrentFilter = 'all'.obs;
  final RxString torrentSortKey = 'added_desc'.obs;
  final RxString errorText = ''.obs;
  final RxSet<int> selectedTorrentIds = <int>{}.obs;
  final RxMap<int, bool> opLoadingById = <int, bool>{}.obs;

  Timer? _pollTimer;
  bool _lowVersionDialogShown = false;
  Duration _pollInterval = const Duration(seconds: 3);
  int _stoppedPollBackoffStep = 0;

  static const Duration _pollIntervalRunning = Duration(seconds: 3);
  static const Duration _pollIntervalStoppedBase = Duration(seconds: 3);
  static const Duration _pollIntervalStoppedMax = Duration(seconds: 60);

  static const torrentSortKeys = <String>[
    'added_desc',
    'added_asc',
    'name_asc',
    'name_desc',
    'progress_desc',
    'progress_asc',
    'size_desc',
    'size_asc',
    'download_speed_desc',
    'upload_speed_desc',
    'ratio_desc',
    'ratio_asc',
  ];

  static const Map<String, String> _torrentSortLabelKeys = {
    'added_desc': 'transmission_sort_added_desc',
    'added_asc': 'transmission_sort_added_asc',
    'name_asc': 'transmission_sort_name_asc',
    'name_desc': 'transmission_sort_name_desc',
    'progress_desc': 'transmission_sort_progress_desc',
    'progress_asc': 'transmission_sort_progress_asc',
    'size_desc': 'transmission_sort_size_desc',
    'size_asc': 'transmission_sort_size_asc',
    'download_speed_desc': 'transmission_sort_download_desc',
    'upload_speed_desc': 'transmission_sort_upload_desc',
    'ratio_desc': 'transmission_sort_ratio_desc',
    'ratio_asc': 'transmission_sort_ratio_asc',
  };

  static const _torrentFields = [
    'id',
    'name',
    'status',
    'addedDate',
    'added_date',
    'percentDone',
    'rateDownload',
    'rateUpload',
    'eta',
    'totalSize',
    'sizeWhenDone',
    'leftUntilDone',
    'haveValid',
    'haveUnchecked',
    'downloadedEver',
    'uploadedEver',
    'uploadRatio',
    'error',
    'errorString',
    'isFinished',
    'labels',
    'downloadDir',
  ];

  @override
  void onInit() {
    super.onInit();
    if (_isServerVersionTooLow()) {
      _applyUnsupportedServerVersion();
      _showLowVersionDialogOnce();
      return;
    }
    refreshAll(showLoading: false);
    _startPolling();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  bool _isServerVersionTooLow() {
    return !ServerVersionUtil.isAtLeast(
      ApiController.instance.serverVersion,
      _requiredServerVersion,
    );
  }

  void _applyUnsupportedServerVersion() {
    errorText.value = 'server_version_too_low'.tr;
  }

  void _showLowVersionDialogOnce() {
    if (_lowVersionDialogShown) return;
    _lowVersionDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
    });
  }

  void _logRefreshError(String scope, Object error, [StackTrace? stack]) {
    debugPrint('[TransmissionController] $scope failed: $error');
    if (stack != null && kDebugMode) {
      debugPrint('$stack');
    }
  }

  void _resetPollInterval() {
    _stoppedPollBackoffStep = 0;
    _pollInterval = _pollIntervalRunning;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _resetPollInterval();
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(_pollInterval, () {
      unawaited(_runPollTick());
    });
  }

  Future<void> _runPollTick() async {
    if (isClosed) return;
    if (_isServerVersionTooLow()) {
      _scheduleNextPoll();
      return;
    }
    try {
      if (isRunning) {
        _resetPollInterval();
        await refreshTorrents(showLoading: false);
        await refreshSession(showLoading: false);
      } else {
        await refreshStatus(showLoading: false);
        if (!isRunning) {
          _stoppedPollBackoffStep = math.min(_stoppedPollBackoffStep + 1, 5);
          final seconds = math.min(
            _pollIntervalStoppedMax.inSeconds,
            _pollIntervalStoppedBase.inSeconds *
                (1 << (_stoppedPollBackoffStep - 1)),
          );
          _pollInterval = Duration(seconds: seconds);
        } else {
          _resetPollInterval();
        }
      }
    } catch (e, stack) {
      _logRefreshError('poll', e, stack);
    } finally {
      if (!isClosed) {
        _scheduleNextPoll();
      }
    }
  }

  bool get isRunning => status['running'] == true;

  String _lastDownloadDirCacheKey() {
    final serverId = Get.isRegistered<ApiController>()
        ? Get.find<ApiController>().state.serverId.trim()
        : '';
    return serverId.isEmpty
        ? _lastDownloadDirKeyPrefix
        : '${_lastDownloadDirKeyPrefix}_$serverId';
  }

  Future<String?> loadLastDownloadDir() async {
    final cached =
        CacheManager().getString(_lastDownloadDirCacheKey())?.trim() ?? '';
    if (cached.isEmpty) return null;
    if (!await _isDownloadDirUsable(cached)) {
      await CacheManager().remove(_lastDownloadDirCacheKey());
      return null;
    }
    return cached;
  }

  Future<bool> validateAndSaveLastDownloadDir(String dir) async {
    final path = dir.trim();
    if (path.isEmpty) return false;
    if (!await _isDownloadDirUsable(path)) return false;
    await CacheManager().setString(_lastDownloadDirCacheKey(), path);
    return true;
  }

  Future<bool> _isDownloadDirUsable(String dir) async {
    return FileApiService.instance.isServerDirWritable(dir);
  }

  Future<void> refreshAll({bool showLoading = true}) async {
    await refreshStatus(showLoading: showLoading);
    await refreshConfig(showLoading: false);
    if (isRunning) {
      await refreshSession(showLoading: false);
      await refreshTorrents(showLoading: false);
    }
  }

  Future<void> refreshStatus({bool showLoading = false}) async {
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.getStatus();
      if (res.success && res.data != null) {
        status.assignAll(Map<String, dynamic>.from(res.data!));
      }
    } catch (e, stack) {
      _logRefreshError('refreshStatus', e, stack);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> refreshConfig({bool showLoading = false}) async {
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.getConfig();
      if (res.success && res.data != null) {
        config.assignAll(Map<String, dynamic>.from(res.data!));
      }
    } catch (e, stack) {
      _logRefreshError('refreshConfig', e, stack);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> refreshSession({bool showLoading = false}) async {
    if (!isRunning) return;
    try {
      final res = await _api.getSession();
      if (res.success && res.data != null) {
        final data = Map<String, dynamic>.from(res.data!);
        final s = data['session'];
        final stats = data['stats'];
        if (s is Map) session.assignAll(Map<String, dynamic>.from(s));
        if (stats is Map) sessionStats.assignAll(Map<String, dynamic>.from(stats));
      }
    } catch (e, stack) {
      _logRefreshError('refreshSession', e, stack);
    }
  }

  Future<void> refreshTorrents({bool showLoading = false}) async {
    if (!isRunning) {
      torrents.clear();
      return;
    }
    if (loadingTorrents.value && !showLoading) return;
    loadingTorrents.value = true;
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.listTorrents(fields: _torrentFields);
      if (res.success && res.data != null) {
        final list = res.data!['torrents'];
        if (list is List) {
          torrents.assignAll(
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
        } else {
          torrents.clear();
        }
      }
    } catch (e, stack) {
      _logRefreshError('refreshTorrents', e, stack);
    } finally {
      loadingTorrents.value = false;
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  List<Map<String, dynamic>> get filteredTorrents {
    final filter = torrentFilter.value;
    return torrents.where((t) {
      final s = _torrentStatus(t);
      switch (filter) {
        case 'downloading':
          return s == 4;
        case 'seeding':
          return s == 6;
        case 'paused':
          return s == 0;
        case 'error':
          return (t['error'] ?? 0) != 0;
        default:
          return true;
      }
    }).toList();
  }

  List<Map<String, dynamic>> get displayTorrents {
    final list = List<Map<String, dynamic>>.from(filteredTorrents);
    list.sort(_compareTorrents);
    return list;
  }

  String torrentSortLabel(String key) {
    final labelKey = _torrentSortLabelKeys[key];
    return labelKey == null ? key : labelKey.tr;
  }

  int _torrentId(Map<String, dynamic> t) => int.tryParse('${t['id']}') ?? 0;

  int _torrentDateAdded(Map<String, dynamic> t) {
    final v = t['addedDate'] ?? t['added_date'] ?? t['dateAdded'] ?? t['date_added'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  String _torrentName(Map<String, dynamic> t) =>
      (t['name']?.toString() ?? '').toLowerCase();

  double _torrentPercent(Map<String, dynamic> t) =>
      ((t['percentDone'] as num?) ?? 0).toDouble();

  int _compareTorrents(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sort = torrentSortKey.value;
    int cmp = 0;
    switch (sort) {
      case 'added_asc':
        cmp = _torrentDateAdded(a).compareTo(_torrentDateAdded(b));
        break;
      case 'name_asc':
        cmp = _torrentName(a).compareTo(_torrentName(b));
        break;
      case 'name_desc':
        cmp = _torrentName(b).compareTo(_torrentName(a));
        break;
      case 'progress_desc':
        cmp = _torrentPercent(b).compareTo(_torrentPercent(a));
        break;
      case 'progress_asc':
        cmp = _torrentPercent(a).compareTo(_torrentPercent(b));
        break;
      case 'size_desc':
        cmp = torrentDisplayTotalSize(b).compareTo(torrentDisplayTotalSize(a));
        break;
      case 'size_asc':
        cmp = torrentDisplayTotalSize(a).compareTo(torrentDisplayTotalSize(b));
        break;
      case 'download_speed_desc':
        cmp = _pickTorrentNum(b, 'rateDownload', 'rate_download')
            .compareTo(_pickTorrentNum(a, 'rateDownload', 'rate_download'));
        break;
      case 'upload_speed_desc':
        cmp = _pickTorrentNum(b, 'rateUpload', 'rate_upload')
            .compareTo(_pickTorrentNum(a, 'rateUpload', 'rate_upload'));
        break;
      case 'ratio_desc':
        cmp = _pickTorrentNum(b, 'uploadRatio', 'upload_ratio')
            .compareTo(_pickTorrentNum(a, 'uploadRatio', 'upload_ratio'));
        break;
      case 'ratio_asc':
        cmp = _pickTorrentNum(a, 'uploadRatio', 'upload_ratio')
            .compareTo(_pickTorrentNum(b, 'uploadRatio', 'upload_ratio'));
        break;
      case 'added_desc':
      default:
        cmp = _torrentDateAdded(b).compareTo(_torrentDateAdded(a));
        break;
    }
    if (cmp != 0) return cmp;
    final idA = _torrentId(a);
    final idB = _torrentId(b);
    final ascSort = sort.endsWith('_asc');
    return ascSort ? idA.compareTo(idB) : idB.compareTo(idA);
  }

  int _torrentStatus(Map<String, dynamic> t) {
    final v = t['status'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  bool isTorrentFinished(Map<String, dynamic> t) {
    if (t['isFinished'] == true) return true;
    if (_torrentStatus(t) == 6) return true;
    final percent = (t['percentDone'] as num?)?.toDouble() ?? 0;
    return percent >= 1.0;
  }

  bool canShowTorrentStart(Map<String, dynamic> t) {
    if (isTorrentFinished(t)) return false;
    return _torrentStatus(t) == 0;
  }

  bool canShowTorrentPause(Map<String, dynamic> t) {
    if (isTorrentFinished(t)) return false;
    return _torrentStatus(t) != 0;
  }

  num _pickTorrentNum(Map<String, dynamic> t, String key, [String? altKey]) {
    final primary = t[key];
    if (primary is num) return primary;
    if (altKey != null) {
      final alt = t[altKey];
      if (alt is num) return alt;
    }
    return 0;
  }

  num torrentDisplayTotalSize(Map<String, dynamic> t) {
    final fromApi = t['displayTotalSize'];
    if (fromApi is num && fromApi > 0) return fromApi;
    final sizeWhenDone = _pickTorrentNum(t, 'sizeWhenDone', 'size_when_done');
    if (sizeWhenDone > 0) return sizeWhenDone;
    return _pickTorrentNum(t, 'totalSize', 'total_size');
  }

  num torrentDisplayDownloadedBytes(Map<String, dynamic> t) {
    final fromApi = t['displayDownloadedBytes'];
    if (fromApi is num && fromApi >= 0) {
      final total = torrentDisplayTotalSize(t);
      if (total > 0) return fromApi.clamp(0, total);
      if (fromApi > 0) return fromApi;
    }

    final sizeWhenDone = _pickTorrentNum(t, 'sizeWhenDone', 'size_when_done');
    final total = torrentDisplayTotalSize(t);
    final leftRaw = t['leftUntilDone'] ?? t['left_until_done'];
    if (sizeWhenDone > 0 && leftRaw is num) {
      return (sizeWhenDone - leftRaw).clamp(0, sizeWhenDone);
    }

    final percent = (_pickTorrentNum(t, 'percentDone', 'percent_done')).toDouble();
    if (total > 0 && percent > 0) {
      return (total * percent).clamp(0, total);
    }

    final have = _pickTorrentNum(t, 'haveValid', 'have_valid') +
        _pickTorrentNum(t, 'haveUnchecked', 'have_unchecked');
    if (have > 0) {
      return total > 0 ? have.clamp(0, total) : have;
    }

    return _pickTorrentNum(t, 'downloadedEver', 'downloaded_ever');
  }

  Future<void> toggleService(bool enabled) async {
    if (serviceOperating.value) return;
    if (enabled && isRunning) {
      await refreshStatus(showLoading: false);
      return;
    }
    if (!enabled && !isRunning) {
      await refreshStatus(showLoading: false);
      return;
    }
    serviceOperating.value = true;
    try {
      DialogUtil.showLoading(
        message: enabled ? 'transmission_starting'.tr : 'transmission_stopping'.tr,
      );
      final res = enabled ? await _api.startService() : await _api.stopService();
      if (res.success) {
        ToastUtil.show(
          enabled ? 'transmission_started'.tr : 'transmission_stopped'.tr,
        );
        await refreshAll(showLoading: false);
        _resetPollInterval();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      serviceOperating.value = false;
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> restartService() async {
    if (serviceOperating.value) return;
    serviceOperating.value = true;
    try {
      DialogUtil.showLoading(message: 'transmission_restarting'.tr);
      final res = await _api.restartService();
      if (res.success) {
        ToastUtil.show('transmission_restarted'.tr);
        await refreshAll(showLoading: false);
        _resetPollInterval();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      serviceOperating.value = false;
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> saveConfig(Map<String, dynamic> body) async {
    if (savingConfig.value) return;
    savingConfig.value = true;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.saveConfig(body);
      if (res.success) {
        ToastUtil.show('transmission_config_saved'.tr);
        if (res.data?['needs_restart'] == true) {
          ToastUtil.show('transmission_restart_required'.tr);
        }
        await refreshConfig(showLoading: false);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      savingConfig.value = false;
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> addTorrent({
    String? url,
    PlatformFile? torrentFile,
    String? serverTorrentPath,
    String? downloadDir,
    bool paused = false,
  }) async {
    final magnetOrUrl = url?.trim() ?? '';
    final serverPath = serverTorrentPath?.trim() ?? '';
    if (magnetOrUrl.isEmpty && torrentFile == null && serverPath.isEmpty) return;
    final dir = downloadDir?.trim() ?? '';
    if (dir.isEmpty) {
      ToastUtil.show('transmission_task_download_dir_required'.tr);
      return;
    }
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      ApiResponse<Map<String, dynamic>> res;
      if (serverPath.isNotEmpty) {
        res = await _api.addTorrent(
          filename: serverPath,
          downloadDir: dir,
          paused: paused,
        );
      } else if (torrentFile != null) {
        final bytes = torrentFile.bytes ??
            await XFile(
              torrentFile.path ?? '',
              name: torrentFile.name,
            ).readAsBytes();
        final metainfo = base64Encode(bytes);
        res = await _api.addTorrent(
          metainfo: metainfo,
          downloadDir: dir,
          paused: paused,
        );
      } else {
        res = await _api.addTorrent(
          url: magnetOrUrl,
          downloadDir: dir,
          paused: paused,
        );
      }
      if (res.success) {
        ToastUtil.show('transmission_torrent_added'.tr);
        await refreshTorrents(showLoading: false);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> addMagnet(String url, {String? downloadDir, bool paused = false}) {
    return addTorrent(url: url, downloadDir: downloadDir, paused: paused);
  }

  Future<void> setTorrentDownloadDir(int id, String location) async {
    final path = location.trim();
    if (path.isEmpty) return;
    opLoadingById[id] = true;
    try {
      final res = await _api.setTorrentLocation(ids: [id], location: path);
      if (res.success) {
        await refreshTorrents(showLoading: false);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } finally {
      opLoadingById[id] = false;
    }
  }

  Future<List<Map<String, dynamic>>> loadTorrentFiles(int id) async {
    final res = await _api.getTorrentFiles(id);
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'operation_failed'.tr);
    }
    final list = res.data!['files'];
    if (list is! List) return const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> saveTorrentFilesSelection({
    required int torrentId,
    required Map<int, bool> wantedByIndex,
  }) async {
    if (wantedByIndex.isEmpty) return;
    final filesWanted = <int>[];
    final filesUnwanted = <int>[];
    for (final entry in wantedByIndex.entries) {
      if (entry.value) {
        filesWanted.add(entry.key);
      } else {
        filesUnwanted.add(entry.key);
      }
    }
    final res = await _api.setTorrentFiles(
      id: torrentId,
      filesWanted: filesWanted,
      filesUnwanted: filesUnwanted,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'operation_failed'.tr);
    }
    await refreshTorrents(showLoading: false);
  }

  Future<void> startTorrent(int id) async {
    opLoadingById[id] = true;
    try {
      final res = await _api.startTorrents([id]);
      if (res.success) await refreshTorrents(showLoading: false);
    } finally {
      opLoadingById[id] = false;
    }
  }

  Future<void> stopTorrent(int id) async {
    opLoadingById[id] = true;
    try {
      final res = await _api.stopTorrents([id]);
      if (res.success) await refreshTorrents(showLoading: false);
    } finally {
      opLoadingById[id] = false;
    }
  }

  Future<void> removeTorrent(int id, {bool deleteLocalData = false}) async {
    opLoadingById[id] = true;
    try {
      final res = await _api.removeTorrents(
        [id],
        deleteLocalData: deleteLocalData,
      );
      if (res.success) await refreshTorrents(showLoading: false);
    } finally {
      opLoadingById[id] = false;
    }
  }

  String statusLabelForTorrent(Map<String, dynamic> t) {
    final s = _torrentStatus(t);
    if ((t['error'] ?? 0) != 0) return 'transmission_status_error'.tr;
    switch (s) {
      case 4:
        return 'transmission_status_downloading'.tr;
      case 6:
        return 'transmission_status_seeding'.tr;
      case 0:
        return 'transmission_status_stopped'.tr;
      case 2:
        return 'transmission_status_checking'.tr;
      default:
        return 'transmission_status_queued'.tr;
    }
  }

  String formatBytes(num? value) {
    final v = (value ?? 0).toDouble();
    if (v < 1024) return '${v.toStringAsFixed(0)} B';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
    if (v < 1024 * 1024 * 1024) {
      return '${(v / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(v / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String formatSpeed(num? bytesPerSec) {
    return '${formatBytes(bytesPerSec)}/s';
  }

  String formatRatio(num? value) {
    final v = (value ?? 0).toDouble();
    if (v < 0) return '-';
    return v.toStringAsFixed(2);
  }

  num _sumTorrentBytes(String field) {
    return torrents.fold<num>(
      0,
      (sum, t) => sum + ((t[field] as num?) ?? 0),
    );
  }

  num _sumTorrentDisplayDownloaded() {
    return torrents.fold<num>(
      0,
      (sum, t) => sum + torrentDisplayDownloadedBytes(t),
    );
  }

  num get overviewTotalDownloaded {
    final fromStats =
        (sessionStats['downloadedBytes'] ?? sessionStats['cumulativeDownloadedBytes']) as num?;
    if ((fromStats ?? 0) > 0) return fromStats!;
    return _sumTorrentDisplayDownloaded();
  }

  num get overviewTotalUploaded {
    final fromStats =
        (sessionStats['uploadedBytes'] ?? sessionStats['cumulativeUploadedBytes']) as num?;
    if ((fromStats ?? 0) > 0) return fromStats!;
    return _sumTorrentBytes('uploadedEver');
  }
}
