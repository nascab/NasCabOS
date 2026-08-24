import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/api/base_api_service.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/server_version_util.dart';
import '../../../utils/toast_util.dart';
import '../service/docker_api_service.dart';

class DockerController extends GetxController {
  static const int _requiredServerVersion = 5;
  final _api = DockerApiService.instance;

  final RxString currentTab = 'overview'.obs;
  final RxString containerStatusFilter = ''.obs;
  final RxList<Map<String, dynamic>> images = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> containers = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> tasks = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> taskLogs = <Map<String, dynamic>>[].obs;

  final RxMap<String, dynamic> status = <String, dynamic>{}.obs;
  final RxMap<String, dynamic> config = <String, dynamic>{}.obs;
  final RxBool dockerAvailable = false.obs;

  final RxBool loadingOverview = false.obs;
  final RxBool loadingImages = false.obs;
  final RxBool loadingContainers = false.obs;
  final RxBool loadingTasks = false.obs;
  final RxBool loadingLogs = false.obs;
  final RxBool savingConfig = false.obs;
  final RxBool dockerServiceOperating = false.obs;
  final RxString selectedTaskId = ''.obs;
  final RxBool taskLogsPollingEnabled = false.obs;
  final RxString errorText = ''.obs;

  Timer? _pollTimer;
  Worker? _tabWorker;
  bool _lowVersionDialogShown = false;
  bool _pollInFlight = false;
  static const Duration _pollInterval = Duration(seconds: 4);

  @override
  void onInit() {
    super.onInit();
    if (_isServerVersionTooLow()) {
      _applyUnsupportedServerVersion();
      _showLowVersionDialogOnce();
      return;
    }
    refreshAll(showLoading: false);
    _tabWorker = ever<String>(currentTab, (tab) async {
      await _refreshCurrentTab(tab);
    });
    _startPolling();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    _tabWorker?.dispose();
    super.onClose();
  }

  bool _isServerVersionTooLow() {
    return !ServerVersionUtil.isAtLeast(
      ApiController.instance.serverVersion,
      _requiredServerVersion,
    );
  }

  void _applyUnsupportedServerVersion() {
    dockerAvailable.value = false;
    errorText.value = 'server_version_too_low'.tr;
    _clearDockerData();
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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        final tab = currentTab.value.trim();
        if (tab == 'overview') {
          await refreshStatus(showLoading: false);
          return;
        }
        await _recoverStatusIfNeeded();
        if (tab == 'tasks') {
          await refreshTasks(showLoading: false);
          final taskId = selectedTaskId.value.trim();
          if (taskLogsPollingEnabled.value && taskId.isNotEmpty) {
            await refreshTaskLogs(taskId, showLoading: false);
          }
        }
      } finally {
        _pollInFlight = false;
      }
    });
  }

  Future<void> _refreshCurrentTab(String tab) async {
    switch (tab.trim()) {
      case 'overview':
        await refreshStatus(showLoading: false);
        break;
      case 'images':
        await _recoverStatusIfNeeded();
        await refreshImages(showLoading: false);
        break;
      case 'containers':
        await _recoverStatusIfNeeded();
        await refreshContainers(showLoading: false);
        break;
      case 'tasks':
        await _recoverStatusIfNeeded();
        await refreshTasks(showLoading: false);
        final taskId = selectedTaskId.value.trim();
        if (taskLogsPollingEnabled.value && taskId.isNotEmpty) {
          await refreshTaskLogs(taskId, showLoading: false);
        }
        break;
      case 'settings':
        await _recoverStatusIfNeeded();
        await refreshConfig(showLoading: false);
        break;
      default:
        break;
    }
  }

  Future<void> _recoverStatusIfNeeded() async {
    if (dockerAvailable.value && errorText.value.trim().isEmpty) {
      return;
    }
    await refreshStatus(showLoading: false);
  }

  Future<void> refreshAll({bool showLoading = false}) async {
    if (_isServerVersionTooLow()) {
      _applyUnsupportedServerVersion();
      _showLowVersionDialogOnce();
      return;
    }
    await refreshStatus(showLoading: showLoading);
    if (!dockerAvailable.value) {
      _clearDockerData();
      return;
    }
    await Future.wait([
      refreshConfig(showLoading: showLoading),
      refreshImages(showLoading: showLoading),
      refreshContainers(showLoading: showLoading),
      refreshTasks(showLoading: showLoading),
    ]);
  }

  Future<void> refreshStatus({bool showLoading = false}) async {
    loadingOverview.value = showLoading;
    final res = await _api.getStatus();
    if (res.success) {
      dockerAvailable.value = true;
      status.assignAll(Map<String, dynamic>.from(res.data ?? const {}));
      errorText.value = '';
    } else {
      status.clear();
      _applyRequestError(res, clearDockerData: true);
    }
    loadingOverview.value = false;
  }

  Future<void> refreshConfig({bool showLoading = false}) async {
    final res = await _api.getConfig();
    if (res.success) {
      config.assignAll(Map<String, dynamic>.from(res.data ?? const {}));
    } else {
      config.clear();
      _applyRequestError(res);
    }
  }

  Future<void> refreshImages({bool showLoading = false}) async {
    loadingImages.value = showLoading;
    final res = await _api.listImages();
    if (res.success) {
      images.assignAll(
        (res.data ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
            .toList(),
      );
    } else {
      images.clear();
      _applyRequestError(res, clearDockerData: _isDockerAvailabilityError(res));
    }
    loadingImages.value = false;
  }

  Future<void> refreshContainers({bool showLoading = false}) async {
    loadingContainers.value = showLoading;
    final res = await _api.listContainers(status: containerStatusFilter.value);
    if (res.success) {
      containers.assignAll(
        (res.data ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
            .toList(),
      );
    } else {
      containers.clear();
      _applyRequestError(res, clearDockerData: _isDockerAvailabilityError(res));
    }
    loadingContainers.value = false;
  }

  Future<void> refreshTasks({bool showLoading = false}) async {
    loadingTasks.value = showLoading;
    final res = await _api.listTasks();
    if (res.success) {
      final rawItems = res.data?['items'];
      final list = rawItems is List ? rawItems : const <dynamic>[];
      tasks.value = list
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
      tasks.refresh();
      final currentTaskId = selectedTaskId.value.trim();
      if (currentTaskId.isNotEmpty &&
          !tasks.any((item) => (item['id']?.toString() ?? '') == currentTaskId)) {
        selectedTaskId.value = '';
        taskLogsPollingEnabled.value = false;
        taskLogs.clear();
        taskLogs.refresh();
      }
    } else {
      tasks.clear();
      tasks.refresh();
      selectedTaskId.value = '';
      taskLogsPollingEnabled.value = false;
      taskLogs.clear();
      taskLogs.refresh();
      _applyRequestError(res, clearDockerData: _isDockerAvailabilityError(res));
    }
    loadingTasks.value = false;
  }

  void selectTask(
    String taskId, {
    bool clearLogs = false,
  }) {
    selectedTaskId.value = taskId.trim();
    if (clearLogs) {
      taskLogs.clear();
      taskLogs.refresh();
    }
  }

  void setTaskLogsPolling(bool enabled) {
    taskLogsPollingEnabled.value = enabled;
  }

  Future<void> openTaskLogs(
    String taskId, {
    bool showLoading = false,
    bool enablePolling = false,
  }) async {
    selectTask(taskId, clearLogs: true);
    setTaskLogsPolling(enablePolling);
    await refreshTaskLogs(taskId, showLoading: showLoading);
  }

  Future<void> refreshTaskLogs(String taskId, {bool showLoading = false}) async {
    if (taskId.trim().isEmpty) {
      selectedTaskId.value = '';
      taskLogs.clear();
      return;
    }
    loadingLogs.value = showLoading;
    selectedTaskId.value = taskId.trim();
    final res = await _api.getTaskLogs(taskId);
    if (res.success) {
      final rawItems = res.data?['items'];
      final list = rawItems is List ? rawItems : const <dynamic>[];
      taskLogs.assignAll(
        list
            .whereType<Map>()
            .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
            .toList(),
      );
      taskLogs.refresh();
    } else {
      taskLogs.clear();
      taskLogs.refresh();
      _applyRequestError(res, clearDockerData: _isDockerAvailabilityError(res));
    }
    loadingLogs.value = false;
  }

  void _clearDockerData() {
    status.clear();
    config.clear();
    images.clear();
    containers.clear();
    tasks.clear();
    taskLogs.clear();
    selectedTaskId.value = '';
    taskLogsPollingEnabled.value = false;
  }

  void _applyRequestError(
    ApiResponse<dynamic> res, {
    bool clearDockerData = false,
  }) {
    errorText.value = _friendlyErrorMessage(res);
    if (clearDockerData || _isDockerAvailabilityError(res)) {
      dockerAvailable.value = false;
      _clearDockerData();
    }
  }

  Future<bool> pullImage({
    required String image,
    String registry = '',
    String tag = '',
    String username = '',
    String password = '',
  }) async {
    final res = await _api.pullImage(
      image: image,
      registry: registry,
      tag: tag,
      username: username,
      password: password,
    );
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    currentTab.value = 'tasks';
    await refreshTasks(showLoading: false);
    final taskId = res.data?['id']?.toString().trim() ?? '';
    if (taskId.isNotEmpty) {
      selectTask(taskId, clearLogs: true);
    }
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> importImage({
    required String archivePath,
  }) async {
    final res = await _api.importImage(archivePath: archivePath);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    currentTab.value = 'tasks';
    await refreshTasks(showLoading: false);
    final taskId = res.data?['id']?.toString().trim() ?? '';
    if (taskId.isNotEmpty) {
      selectTask(taskId, clearLogs: true);
    }
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> deleteImage(String imageId, {String reference = ''}) async {
    final res = await _api.deleteImage(imageId, reference: reference);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshImages(showLoading: false);
    ToastUtil.show(res.message ?? 'delete_success'.tr);
    return true;
  }

  Future<bool> tagImage({
    required String imageId,
    required String repository,
    required String tag,
    String sourceReference = '',
  }) async {
    final res = await _api.tagImage(
      imageId: imageId,
      repository: repository,
      tag: tag,
      sourceReference: sourceReference,
    );
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshImages(showLoading: false);
    await refreshContainers(showLoading: false);
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> createContainer(Map<String, dynamic> body) async {
    final res = await _api.createContainer(body);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshContainers(showLoading: false);
    final command = res.data?['command']?.toString().trim() ?? '';
    if (command.isNotEmpty) {
      await copyCommand(command, toastKey: 'docker_copy_command_success');
    }
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> startContainer(String id) async {
    final res = await _api.startContainer(id);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshContainers(showLoading: false);
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> stopContainer(String id, {int timeout = 10}) async {
    final res = await _api.stopContainer(id, timeout: timeout);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshContainers(showLoading: false);
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> deleteContainer(String id, {bool force = false}) async {
    final res = await _api.deleteContainer(id, force: force);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshContainers(showLoading: false);
    ToastUtil.show(res.message ?? 'delete_success'.tr);
    return true;
  }

  Future<Map<String, dynamic>?> fetchContainerLogs({
    required String containerId,
    String since = '',
    String until = '',
    int tail = 200,
    bool streamOutput = false,
  }) async {
    final res = await _api.getContainerLogs(
      containerId: containerId,
      since: since,
      until: until,
      tail: tail,
      streamOutput: streamOutput,
    );
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return null;
    }
    if (streamOutput) {
      currentTab.value = 'tasks';
      await refreshTasks(showLoading: false);
      final taskId = res.data?['id']?.toString().trim() ?? '';
      if (taskId.isNotEmpty) {
        selectTask(taskId, clearLogs: true);
      }
    }
    return res.data;
  }

  Future<bool> cancelTask(String taskId) async {
    final normalizedTaskId = taskId.trim();
    Map<String, dynamic>? previousTask;
    final index = tasks.indexWhere(
      (item) => (item['id']?.toString() ?? '') == normalizedTaskId,
    );
    if (index >= 0) {
      previousTask = Map<String, dynamic>.from(tasks[index]);
      final next = Map<String, dynamic>.from(tasks[index]);
      next['status'] = 'cancelled';
      next['canCancel'] = false;
      next['finishedAt'] = DateTime.now().toIso8601String();
      tasks[index] = next;
      tasks.refresh();
    }
    final res = await _api.cancelTask(taskId);
    if (!res.success) {
      if (index >= 0 && previousTask != null) {
        tasks[index] = previousTask;
        tasks.refresh();
      }
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    final currentTask = res.data == null
        ? null
        : Map<String, dynamic>.from(res.data!.map((key, value) => MapEntry(key.toString(), value)));
    if (index >= 0 && currentTask != null) {
      tasks[index] = currentTask;
      tasks.refresh();
    }
    await refreshTasks(showLoading: false);
    if (taskLogsPollingEnabled.value && selectedTaskId.value.trim() == normalizedTaskId) {
      await refreshTaskLogs(taskId, showLoading: false);
    }
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> deleteTask(String taskId) async {
    final res = await _api.deleteTask(taskId);
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    tasks.removeWhere((item) => (item['id']?.toString() ?? '') == taskId.trim());
    tasks.refresh();
    final currentTaskId = selectedTaskId.value.trim();
    if (currentTaskId == taskId.trim()) {
      selectedTaskId.value = '';
      taskLogsPollingEnabled.value = false;
      taskLogs.clear();
      taskLogs.refresh();
    }
    await refreshTasks(showLoading: false);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  Future<bool> saveProxyConfig({
    required String httpProxy,
    required String httpsProxy,
    required String noProxy,
  }) async {
    final res = await _api.setProxyConfig(
      httpProxy: httpProxy,
      httpsProxy: httpsProxy,
      noProxy: noProxy,
    );
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshConfig(showLoading: false);
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> saveConfigContent(String content) async {
    savingConfig.value = true;
    final res = await _api.saveConfig(content);
    savingConfig.value = false;
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    await refreshConfig(showLoading: false);
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<bool> toggleDockerService() async {
    if (dockerServiceOperating.value) return false;
    dockerServiceOperating.value = true;
    final shouldStart = !dockerAvailable.value;
    final res = shouldStart ? await _api.startDocker() : await _api.stopDocker();
    dockerServiceOperating.value = false;
    if (!res.success) {
      _applyRequestError(res);
      ToastUtil.show(_friendlyErrorMessage(res));
      return false;
    }
    currentTab.value = 'tasks';
    await refreshTasks(showLoading: false);
    final taskId = res.data?['id']?.toString().trim() ?? '';
    if (taskId.isNotEmpty) {
      selectTask(taskId, clearLogs: true);
      setTaskLogsPolling(true);
      await refreshTaskLogs(taskId, showLoading: false);
    }
    ToastUtil.show(res.message ?? 'operation_success'.tr);
    return true;
  }

  Future<void> copyCommand(
    String text, {
    String toastKey = 'docker_copy_command_success',
  }) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    ToastUtil.show(toastKey.tr);
  }

  String _friendlyErrorMessage(ApiResponse<dynamic> res) {
    final apiErrorKey = res.apiErrorKey?.trim() ?? '';
    final message = res.message?.trim() ?? '';
    if (_isDockerUnavailable(apiErrorKey, message)) {
      return _translatedOrFallback(
        'docker_error_daemon_unavailable',
        fallback: message,
      );
    }
    if (_isDockerCommandMissing(apiErrorKey, message)) {
      return _translatedOrFallback(
        'docker_error_command_not_found',
        fallback: message,
      );
    }
    if (_isDockerPermissionDenied(message)) {
      return _translatedOrFallback(
        'docker_error_permission_denied',
        fallback: message,
      );
    }
    if (_isDockerImageInUse(apiErrorKey, message)) {
      return _translatedOrFallback(
        'docker_error_image_in_use',
        fallback: message,
      );
    }
    if (apiErrorKey == 'docker.INVALID_CONFIG_JSON') {
      return _translatedOrFallback(
        'docker_invalid_config_json',
        fallback: message,
      );
    }
    if (apiErrorKey == 'docker.START_FAILED') {
      return _translatedOrFallback(
        'docker_start_failed',
        fallback: message,
      );
    }
    if (apiErrorKey == 'docker.STOP_FAILED') {
      return _translatedOrFallback(
        'docker_stop_failed',
        fallback: message,
      );
    }
    if (apiErrorKey == 'docker.RESTART_FAILED') {
      return _translatedOrFallback(
        'docker_restart_failed',
        fallback: message,
      );
    }
    if (message.isNotEmpty) return message;
    return 'operation_failed'.tr;
  }

  bool _isDockerAvailabilityError(ApiResponse<dynamic> res) {
    final apiErrorKey = res.apiErrorKey?.trim() ?? '';
    final message = res.message?.trim() ?? '';
    return _isDockerUnavailable(apiErrorKey, message) ||
        _isDockerCommandMissing(apiErrorKey, message);
  }

  bool _isDockerUnavailable(String apiErrorKey, String message) {
    if (apiErrorKey == 'docker.DOCKER_UNAVAILABLE') return true;
    final lower = message.toLowerCase();
    return lower.contains('cannot connect to the docker daemon') ||
        lower.contains('cannot connect to the docker daemon at') ||
        lower.contains('failed to connect to the docker api at') ||
        lower.contains('check if the path is correct and if the daemon is running') ||
        lower.contains('is the docker daemon running') ||
        lower.contains('docker daemon is not running') ||
        lower.contains('error during connect') ||
        lower.contains(
          'this error may indicate that the docker daemon is not running',
        ) ||
        lower.contains('docker desktop is not running') ||
        (lower.contains('dial unix') && lower.contains('docker.sock')) ||
        (lower.contains('open //./pipe/docker_engine') &&
            lower.contains('the system cannot find the file specified'));
  }

  bool _isDockerCommandMissing(String apiErrorKey, String message) {
    if (apiErrorKey == 'docker.DOCKER_COMMAND_NOT_FOUND') return true;
    final lower = message.toLowerCase();
    return lower.contains('spawn docker enoent') ||
        lower.contains('docker: command not found') ||
        lower.contains('commandnotfoundexception') ||
        (lower.contains('objectnotfound: (docker:string)') &&
            lower.contains('fullyqualifiederrorid'));
  }

  bool _isDockerPermissionDenied(String message) {
    final lower = message.toLowerCase();
    return lower.contains('permission denied while trying to connect to the docker daemon socket') ||
        lower.contains('dial unix /var/run/docker.sock: connect: permission denied') ||
        lower.contains('got permission denied while trying to connect to the docker daemon socket');
  }

  bool _isDockerImageInUse(String apiErrorKey, String message) {
    if (apiErrorKey == 'docker.IMAGE_IN_USE') return true;
    final lower = message.toLowerCase();
    return (lower.contains('conflict') &&
            lower.contains('unable to remove repository reference')) ||
        (lower.contains('conflict') &&
            lower.contains('image is being used by running container')) ||
        (lower.contains('conflict') &&
            lower.contains('container') &&
            lower.contains('is using its referenced image'));
  }

  String _translatedOrFallback(String key, {required String fallback}) {
    final translated = key.tr;
    if (translated != key) return translated;
    if (fallback.isNotEmpty) return fallback;
    return 'operation_failed'.tr;
  }
}
