import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'p2p_rtc_stub.dart' if (dart.library.html) 'p2p_rtc_web.dart';
import 'p2p_ws_factory_io.dart'
    if (dart.library.html) 'p2p_ws_factory_web.dart'
    as p2p_ws_factory;
import 'p2p_signaling_binary.dart';
import 'api_parts/p2p_channel_util.dart';
import '../../utils/cache_manager.dart';
import '../../utils/app_window_title.dart';
import '../../utils/local_web_asset_server.dart';
import '../../utils/server_version_util.dart';
import 'api_state.dart';
import '../../modules/auth/service/auth_api_service.dart';
import '../../modules/auth/service/server_storage_service.dart';
import '../../modules/auth/service/response/server_status_response.dart';
import '../../modules/auth/beans/server_info_bean.dart';
import '../../modules/photoBackup/controller/photo_backup_controller.dart';
import '../../modules/base/components/custom_extended_image.dart';
import '../config/app_config.dart';
import '../config/nascab_endpoints.dart';
import 'http_client_factory.dart'
    if (dart.library.html) 'http_client_factory_web.dart'
    if (dart.library.io) 'http_client_factory_io.dart';

part 'api_parts/api_controller_auth.dart';
part 'api_parts/api_controller_failover.dart';
part 'api_parts/api_controller_p2p.dart';
part 'api_parts/api_controller_urls.dart';

enum DevConnectMode { auto, direct, p2p, p2pDirect, p2pRelay }

enum P2pIcePreference { auto, directOnly, relayOnly }

enum P2pTransportKind { unknown, direct, relay }

class ApiController extends GetxController {
  static ApiController get instance => Get.find<ApiController>();

  static String get signalApiBaseUrl => NasCabEndpoints.signalBaseUrl;
  static const String quickShareAesKey = '!N@S#CB1298AS3HADSF!@';
  static const String p2pBaseUrl = 'http://p2p.local';
  static const String _cacheKeyDevConnectMode = 'dev_connect_mode';

  ApiState _state = ApiState(serverId: '', baseUrl: _getDefaultBaseUrl());

  ApiState get state => _state;

  Timer? _refreshTimer;

  /// 合并并发刷新，避免滚动 refresh 时多请求竞态导致误报会话过期（对齐 tv Swift 侧实现）。
  Future<bool>? _refreshAuthTokenInFlight;
  WebSocketChannel? _p2pChannel;
  StreamSubscription? _p2pSub;
  Timer? _p2pWsHeartbeatTimer;
  Timer? _p2pReconnectTimer;
  Future<void> _p2pConnectQueue = Future.value();
  int _p2pReconnectAttempts = 0;
  int _p2pConnectToken = 0;
  bool _p2pAllowReconnect = false;
  String _p2pLastPairCode = '';
  String _p2pSessionId = '';
  String _p2pPairCode = '';
  List<dynamic> _p2pIceServers = const [];
  P2pRtcClient? _p2pRtc;
  bool _p2pReady = false;
  Object? _p2pLastConnectError;
  P2pIcePreference _p2pIcePreference = P2pIcePreference.auto;
  P2pIcePreference _p2pActiveIcePreference = P2pIcePreference.auto;
  P2pTransportKind _p2pTransportKind = P2pTransportKind.unknown;
  String _p2pRelayAddress = '';
  bool _p2pAutoSwitchInProgress = false;
  int _p2pLastAutoSwitchAttemptAtMs = 0;
  int _p2pLastAutoSwitchProbeAtMs = 0;
  int _p2pNextConnectAllowedAtMs = 0;
  Future<bool>? _p2pReconnectInFlight;
  Future<bool>? _manualConnectChannelRefreshInFlight;

  Future<bool> _failoverQueue = Future.value(false);
  DateTime _failoverCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Future<bool>? _requestRecoveryInFlight;

  // 全局网络类型变化监控（WiFi ↔ 5G 等切换时主动探测所有通道）
  StreamSubscription<List<ConnectivityResult>>? _globalNetMonitorSub;
  Timer? _globalNetChangeProbeTimer;
  List<ConnectivityResult> _globalLastConnectivity = const [];
  bool _globalNetChangeProbeLocked = false;
  int _globalNetChangeProbeMsAt = 0;

  static const Duration _failoverProbeTimeout = Duration(seconds: 2);
  static const Duration _requestFailureProbeCooldown = Duration(seconds: 5);

  DevConnectMode _devConnectMode = DevConnectMode.auto;

  int faceImageTimestamp = DateTime.now().millisecondsSinceEpoch;

  final _p2pReadyController = StreamController<bool>.broadcast();
  final _p2pConnectionStateController = StreamController<String>.broadcast();
  Stream<bool> get onP2pReadyChanged => _p2pReadyController.stream;
  Stream<String> get onP2pConnectionStateChanged =>
      _p2pConnectionStateController.stream;

  final RxInt connectChannelRevision = 0.obs;
  final RxBool connectChannelRefreshing = false.obs;

  void _bumpConnectChannelRevision() {
    connectChannelRevision.value++;
  }

  String get connectChannelDisplayValue {
    final isRelay =
        isP2pMode &&
        (devConnectMode == DevConnectMode.p2pRelay ||
            p2pTransportKind == P2pTransportKind.relay);
    final relayAddress = p2pRelayAddress.trim();
    if (isP2pMode) {
      if (isRelay) {
        return relayAddress.isNotEmpty ? 'P2P $relayAddress' : 'P2P ';
      }
      return 'P2P';
    }
    return baseUrl;
  }

  @override
  void onInit() {
    super.onInit();
    _loadStoredTokens();
    _loadDevConnectMode();
    _startTokenRefreshTimer();
    if (!kIsWeb) {
      LocalWebAssetServer.instance.setP2pActive(baseUrl.trim() == p2pBaseUrl);
    }
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    _p2pReconnectTimer?.cancel();
    _globalNetChangeProbeTimer?.cancel();
    _globalNetMonitorSub?.cancel();
    _p2pReadyController.close();
    _p2pConnectionStateController.close();
    super.onClose();
  }

  /// 获取默认的基础URL
  static String _getDefaultBaseUrl() {
    if (kIsWeb) {
      if (kDebugMode) {
        // 开发环境：返回本地服务器URL
        return AppConfig.localhostBaseUrl;
      } else {
        // Web端：获取当前浏览器的地址栏基础URL 打包模式获取地址栏
        final currentUrl = Uri.base.toString();
        final uri = Uri.parse(currentUrl);
        return '${uri.scheme}://${uri.authority}';
      }
    } else {
      // 非Web端：默认URL，可以后续修改
      return AppConfig.localhostBaseUrl;
    }
  }

  /// 设置基础URL
  void setBaseUrl(String baseUrl) {
    _state = _state.copyWith(baseUrl: baseUrl);
    _bumpConnectChannelRevision();
    try {
      CacheManager().setString('auth_baseUrl', baseUrl);
    } catch (_) {}
    if (!kIsWeb) {
      final isP2p = baseUrl.trim() == p2pBaseUrl;
      LocalWebAssetServer.instance.setP2pActive(isP2p);
    }
  }

  bool get isP2pEnabled => _p2pChannel != null;
  String get p2pPairCode => _p2pPairCode;
  bool get isP2pReady => _p2pReady;
  bool get isP2pMode => baseUrl.trim() == p2pBaseUrl;

  /// 是否为 P2P 中继模式（用户选择中继或当前实际走中继）
  bool get isP2pRelayMode =>
      isP2pMode &&
      (devConnectMode == DevConnectMode.p2pRelay ||
          p2pTransportKind == P2pTransportKind.relay);

  DevConnectMode get devConnectMode => _devConnectMode;
  P2pTransportKind get p2pTransportKind => _p2pTransportKind;
  String get p2pRelayAddress => _p2pRelayAddress;
  Object? get p2pLastConnectError => _p2pLastConnectError;

  void _setP2pReady(bool value) {
    if (_p2pReady == value) return;
    _p2pReady = value;
    _p2pReadyController.add(value);
  }

  void _emitConnectionState(String state) {
    _p2pConnectionStateController.add(state);
  }

  Future<Map<String, String>> getP2pTransportStats() async {
    final rtc = _p2pRtc;
    if (rtc == null) return {};
    try {
      return await rtc.getTransportStats();
    } catch (_) {
      return {};
    }
  }

  void _loadDevConnectMode() {
    try {
      final raw = (CacheManager().getString(_cacheKeyDevConnectMode) ?? '')
          .trim()
          .toLowerCase();
      _devConnectMode = _parseDevConnectMode(raw);
    } catch (_) {}
  }

  DevConnectMode _parseDevConnectMode(String raw) {
    switch (raw) {
      case 'direct':
        return DevConnectMode.direct;
      case 'p2p':
        return DevConnectMode.p2p;
      case 'p2pdirect':
        return DevConnectMode.p2pDirect;
      case 'p2prelay':
        return DevConnectMode.p2pRelay;
      case 'auto':
      default:
        return DevConnectMode.auto;
    }
  }

  String _serializeDevConnectMode(DevConnectMode mode) {
    switch (mode) {
      case DevConnectMode.auto:
        return 'auto';
      case DevConnectMode.direct:
        return 'direct';
      case DevConnectMode.p2p:
        return 'p2p';
      case DevConnectMode.p2pDirect:
        return 'p2pDirect';
      case DevConnectMode.p2pRelay:
        return 'p2pRelay';
    }
  }

  Future<void> setDevConnectMode(
    DevConnectMode mode, {
    bool applyNow = true,
  }) async {
    _devConnectMode = mode;
    _bumpConnectChannelRevision();
    try {
      CacheManager().setString(
        _cacheKeyDevConnectMode,
        _serializeDevConnectMode(mode),
      );
    } catch (_) {}
    if (applyNow) {
      await applyDevConnectModeNow();
    }
  }

  Future<void> applyDevConnectModeNow() async {
    if (_devConnectMode == DevConnectMode.auto) {
      await refreshConnectChannel();
      return;
    }

    final serverId = _state.serverId.trim();
    if (serverId.isEmpty) return;
    final serverInfo = _loadServerInfoById(serverId);
    if (serverInfo == null) return;

    if (_devConnectMode == DevConnectMode.direct) {
      final ok = await _switchDevToDirect(
        serverInfo,
        expectedServerId: serverId,
      );
      if (!ok) throw Exception('dev_switch_direct_failed');
      return;
    }

    final P2pIcePreference pref;
    switch (_devConnectMode) {
      case DevConnectMode.p2pDirect:
        pref = P2pIcePreference.directOnly;
        break;
      case DevConnectMode.p2pRelay:
        pref = P2pIcePreference.relayOnly;
        break;
      case DevConnectMode.p2p:
      case DevConnectMode.auto:
      case DevConnectMode.direct:
        pref = P2pIcePreference.auto;
        break;
    }

    final ok = await _switchDevToP2p(
      serverInfo,
      expectedServerId: serverId,
      icePreference: pref,
    );
    if (!ok) throw Exception('dev_switch_p2p_failed');
  }

  static String? validatePairCodeText(String? value) {
    final s = value?.trim() ?? '';
    if (s.isEmpty) return 'server_pair_code_empty'.tr;
    if (s.length < 4) return 'server_pair_code_invalid'.tr;
    if (s.length > 32) return 'server_pair_code_invalid'.tr;
    return null;
  }

  /// 配对码 session/create 等建连阶段抛出的异常，应用 [formatP2pConnectError] 展示友好文案。
  static bool shouldFormatAsP2pConnectError(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString();
    return s.contains('pair_code_empty') ||
        s.contains('pair_session_') ||
        s.contains('pair_ws_url_invalid') ||
        s.contains('p2p_ws_') ||
        s.contains('p2p_ws_closed') ||
        s.contains('p2p_rtc_init_failed') ||
        s.contains('p2p_not_connected') ||
        s.contains('p2p_relay_not_available');
  }

  static String formatP2pConnectError(Object e) {
    if (e is TimeoutException) {
      return 'server_connect_timeout'.tr;
    }
    final s = e.toString();
    if (s.contains('pair_code_empty')) return 'server_pair_code_empty'.tr;
    if (s.contains('pair_session_http_429')) {
      return 'P2P_TOO_MANY_REQUESTS'.tr;
    }
    if (s.contains('pair_session_http_')) return 'server_pair_code_invalid'.tr;
    if (s.contains('pair_session_invalid')) {
      return 'server_p2p_session_invalid'.tr;
    }
    if (s.contains('pair_ws_url_invalid')) {
      return 'server_p2p_ws_url_invalid'.tr;
    }
    if (s.contains('p2p_relay_not_available')) {
      return 'server_p2p_relay_not_available'.tr;
    }
    if (s.contains('p2p_ws_error') || s.contains('p2p_ws_closed')) {
      return 'server_p2p_channel_failed'.tr;
    }
    if (s.contains('p2p_rtc_init_failed') || s.contains('p2p_not_connected')) {
      return 'server_p2p_channel_failed'.tr;
    }
    return 'server_connect_failed_with_error'.trParams({'error': '$e'});
  }
}

class _FailoverCandidate {
  const _FailoverCandidate({required this.baseUrl, required this.isP2p});

  final String baseUrl;
  final bool isP2p;
}
