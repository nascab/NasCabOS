import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../api/base_api_service.dart';
import '../user/current_user_controller.dart';

class _HwApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> getMetrics() {
    return apiGet<Map<String, dynamic>>(
      '/api/hw/metrics',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }
}

class HwMetricsController extends GetxController {
  static HwMetricsController get instance => Get.find<HwMetricsController>();

  final _service = _HwApiService();
  final RxBool _running = false.obs;
  final RxBool _fetching = false.obs;
  final RxBool _isForeground = true.obs;
  final Rxn<Map<String, dynamic>> _metrics = Rxn<Map<String, dynamic>>();
  final RxnString _lastError = RxnString();
  Timer? _timer;
  DateTime? _lastRequestAt;
  _LifecycleObserver? _lifecycleObserver;

  bool get isRunning => _running.value;
  bool get isFetching => _fetching.value;
  bool get isForeground => _isForeground.value;
  Map<String, dynamic>? get metrics => _metrics.value;
  String? get lastError => _lastError.value;

  static const Duration _interval = Duration(seconds: 3);

  @override
  void onInit() {
    super.onInit();
    _lifecycleObserver = _LifecycleObserver(onChanged: _onLife);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  @override
  void onClose() {
    stop();
    final obs = _lifecycleObserver;
    if (obs != null) {
      WidgetsBinding.instance.removeObserver(obs);
      _lifecycleObserver = null;
    }
    super.onClose();
  }

  void start() {
    if (_running.value) return;
    _running.value = true;
    _scheduleNext();
  }

  void stop() {
    _running.value = false;
    _timer?.cancel();
    _timer = null;
  }

  void _onLife(AppLifecycleState state) {
    final isFg = state == AppLifecycleState.resumed;
    if (_isForeground.value == isFg) return;
    _isForeground.value = isFg;
    if (!isFg) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_running.value) {
      _scheduleNext();
    }
  }

  bool get _shouldSchedule {
    if (isClosed) return false;
    if (!_running.value) return false;
    if (!_isForeground.value) return false;
    return true;
  }

  bool get _shouldFetch {
    if (!_shouldSchedule) return false;
    if (!CurrentUserController.instance.isLoggedIn) return false;
    return true;
  }

  void _scheduleNext() {
    if (!_shouldSchedule) return;
    if (_timer?.isActive == true) return;

    final now = DateTime.now();
    final last = _lastRequestAt;
    final elapsed = last == null ? _interval : now.difference(last);
    final delay = elapsed >= _interval ? Duration.zero : (_interval - elapsed);
    _timer = Timer(delay, () {
      unawaited(_tick());
    });
  }

  Future<void> _tick() async {
    if (!_shouldSchedule) return;
    if (!_shouldFetch) {
      _timer?.cancel();
      _timer = null;
      _scheduleNext();
      return;
    }
    if (_fetching.value) {
      _timer?.cancel();
      _timer = null;
      _scheduleNext();
      return;
    }

    _fetching.value = true;
    _lastRequestAt = DateTime.now();
    try {
      final resp = await _service.getMetrics();
      if (resp.success) {
        _metrics.value = resp.data;
        _lastError.value = null;
      } else {
        _lastError.value = resp.message;
        _metrics.value = null;
      }
    } catch (e) {
      _lastError.value = e.toString();
    } finally {
      _fetching.value = false;
    }

    _timer?.cancel();
    _timer = null;
    _scheduleNext();
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  final void Function(AppLifecycleState) onChanged;
  _LifecycleObserver({required this.onChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state);
  }
}
