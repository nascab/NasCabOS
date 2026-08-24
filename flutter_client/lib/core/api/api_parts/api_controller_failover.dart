part of '../api_controller.dart';

extension ApiControllerFailover on ApiController {
  Future<bool> refreshConnectChannel() {
    final existing = _manualConnectChannelRefreshInFlight;
    if (existing != null) return existing;
    final task = _refreshConnectChannelLocked();
    _manualConnectChannelRefreshInFlight = task;
    connectChannelRefreshing.value = true;
    return task.whenComplete(() {
      if (identical(_manualConnectChannelRefreshInFlight, task)) {
        _manualConnectChannelRefreshInFlight = null;
      }
      connectChannelRefreshing.value = false;
    });
  }

  Future<bool> _refreshConnectChannelLocked() async {
    if (!isAuthenticated) return false;

    final recoveryInFlight = _requestRecoveryInFlight;
    if (recoveryInFlight != null) {
      return recoveryInFlight;
    }

    final serverId = _state.serverId.trim();
    if (serverId.isEmpty) return false;

    final serverInfos = _loadServerInfosById(serverId);
    if (serverInfos.isEmpty) return false;

    final task = _failoverQueue.then((_) async {
      _globalNetChangeProbeLocked = true;
      _globalNetChangeProbeMsAt = DateTime.now().millisecondsSinceEpoch;
      _failoverCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        return await _probePreferredChannel(
          serverInfos,
          expectedServerId: serverId,
          reconnectCurrentP2p: false,
        );
      } finally {
        _globalNetChangeProbeLocked = false;
      }
    });
    _requestRecoveryInFlight = task;
    _failoverQueue = task.catchError((_) => false);
    return task.whenComplete(() {
      if (identical(_requestRecoveryInFlight, task)) {
        _requestRecoveryInFlight = null;
      }
    });
  }

  Future<bool> maybeFailoverOnRequestError({
    required Object error,
    required String endpoint,
  }) {
    if (_devConnectMode != DevConnectMode.auto) {
      return Future.value(false);
    }
    if (!isAuthenticated) return Future.value(false);
    if (!_shouldFailoverForEndpoint(endpoint)) return Future.value(false);
    if (!_isTransportError(error)) return Future.value(false);

    final serverId = _state.serverId.trim();
    if (serverId.isEmpty) return Future.value(false);

    final now = DateTime.now();
    if (now.isBefore(_failoverCooldownUntil)) return Future.value(false);
    _failoverCooldownUntil = now.add(
      ApiController._requestFailureProbeCooldown,
    );

    final currentBaseUrl = baseUrl.trim();
    if (currentBaseUrl.isEmpty) return Future.value(false);

    final inFlight = _requestRecoveryInFlight;
    if (inFlight != null) {
      print('🟡 [Failover] 已有请求恢复流程在执行，复用当前恢复任务');
      return inFlight;
    }

    print(
      '🟡 [Failover] 请求失败触发重检: endpoint=$endpoint, baseUrl=$currentBaseUrl, error=$error',
    );
    final task = _failoverQueue.then((_) {
      return _performFailoverLocked(
        serverId: serverId,
        failedBaseUrl: currentBaseUrl,
      );
    });
    _requestRecoveryInFlight = task;
    _failoverQueue = task.catchError((_) => false);
    return task.whenComplete(() {
      if (identical(_requestRecoveryInFlight, task)) {
        _requestRecoveryInFlight = null;
      }
    });
  }

  bool _shouldFailoverForEndpoint(String endpoint) {
    final ep = endpoint.trim();
    if (ep.isEmpty) return false;
    if (ep == '/health') return false;
    if (ep == '/api/hw/metrics') return false;
    if (ep.startsWith('/api/auth/login')) return false;
    if (ep.startsWith('/api/auth/refreshJwt')) return false;
    if (ep.startsWith('/api/auth/2fa/')) return false;
    if (ep.startsWith('/api/p2p/')) return false;
    return true;
  }

  bool _isTransportError(Object error) {
    if (error is TimeoutException) return true;
    if (!kIsWeb && error is SocketException) return true;
    if (!kIsWeb && error is HandshakeException) return true;
    if (error is http.ClientException) return true;

    final s = error.toString().toLowerCase();
    if (s.contains('socketexception')) return true;
    if (s.contains('connection refused')) return true;
    if (s.contains('timed out')) return true;
    if (s.contains('handshake')) return true;
    if (s.contains('network is unreachable')) return true;
    if (s.contains('name or service not known')) return true;
    if (s.contains('failed host lookup')) return true;

    if (s.contains('p2p_not_connected')) return true;
    if (s.contains('p2p_disconnected')) return true;
    if (s.contains('p2p_ws_error')) return true;
    if (s.contains('p2p_ws_closed')) return true;
    if (s.contains('p2p_dc_closed')) return true;
    if (s.contains('p2p_dc_error')) return true;
    if (s.contains('p2p_dc_not_open')) return true;

    return false;
  }

  Future<bool> _performFailoverLocked({
    required String serverId,
    required String failedBaseUrl,
  }) async {
    if (_state.serverId.trim() != serverId) return false;

    final serverInfos = _loadServerInfosById(serverId);
    if (serverInfos.isEmpty) return false;
    return _probePreferredChannel(
      serverInfos,
      expectedServerId: serverId,
      reconnectCurrentP2p: true,
      failedBaseUrl: failedBaseUrl,
    );
  }

  Future<bool> _probePreferredChannel(
    List<ServerInfoBean> serverInfos, {
    required String expectedServerId,
    required bool reconnectCurrentP2p,
    String? failedBaseUrl,
  }) async {
    final failed = _normalizeBaseUrl(failedBaseUrl ?? '');
    final seen = <String>{};
    final orderedServerInfos = _orderServerInfosForCurrentBaseUrl(serverInfos);
    for (final rawUrl in _buildDirectProbeCandidates(
      orderedServerInfos,
      failedBaseUrl: failed,
    )) {
      final url = _normalizeBaseUrl(rawUrl);
      if (url.isEmpty || !_isValidHttpBaseUrl(url)) continue;
      if (!seen.add(url)) continue;

      print('🟡 [Failover] 探测直连候选: $url');
      final ok = await _probeHealthDirect(
        url,
        expectedServerId: expectedServerId,
      );
      if (!ok) {
        print('🟡 [Failover] 直连探测失败: $url');
        continue;
      }
      print('🟢 [Failover] 直连探测成功: $url');

      if (_normalizeBaseUrl(baseUrl) != url) {
        final wasP2p = isP2pMode;
        setBaseUrl(url);
        if (wasP2p) {
          unawaited(_disconnectP2pIfNotInUse());
        }
      }
      return true;
    }

    final p2pServerInfo = orderedServerInfos.firstWhereOrNull(
      (item) => (item.pairCode ?? '').trim().isNotEmpty,
    );
    final pairCode = (p2pServerInfo?.pairCode ?? '').trim();
    if (pairCode.isEmpty) {
      print('🔴 [Failover] 无可用 pairCode，无法切换到 P2P');
      return false;
    }

    if (!reconnectCurrentP2p && isP2pMode && isP2pReady) {
      _p2pLastAutoSwitchAttemptAtMs = 0;
      _p2pLastAutoSwitchProbeAtMs = 0;
      if (_p2pTransportKind == P2pTransportKind.relay) {
        print('🟡 [Failover] 网络变化后尝试将 P2P relay 升级为直连');
        await _runP2pAutoSwitchProbe(ignoreProbeThrottle: true);
      }
      return isP2pReady;
    }

    print('🟡 [Failover] 开始切换到 P2P: pairCode=$pairCode');
    return _trySwitchToP2p(p2pServerInfo!, expectedServerId: expectedServerId);
  }

  List<ServerInfoBean> _loadServerInfosById(String serverId) {
    final target = serverId.trim();
    if (target.isEmpty) return const [];
    final currentUsername =
        (CurrentUserController.instance.current?.username ?? '').trim();
    final all = ServerStorageService.loadServers();
    final matched = <ServerInfoBean>[];
    if (currentUsername.isNotEmpty) {
      for (final s in all) {
        if (s.serverId.trim() != target) continue;
        if ((s.username ?? '').trim() == currentUsername) {
          matched.add(s);
        }
      }
      if (matched.isNotEmpty) return matched;
    }
    for (final s in all) {
      if (s.serverId.trim() == target) matched.add(s);
    }
    return matched;
  }

  ServerInfoBean? _loadServerInfoById(String serverId) {
    final infos = _orderServerInfosForCurrentBaseUrl(
      _loadServerInfosById(serverId),
    );
    if (infos.isEmpty) return null;
    return infos.first;
  }

  List<ServerInfoBean> _orderServerInfosForCurrentBaseUrl(
    List<ServerInfoBean> serverInfos,
  ) {
    final current = _normalizeBaseUrl(baseUrl);
    final matched = <ServerInfoBean>[];
    final others = <ServerInfoBean>[];
    for (final serverInfo in serverInfos) {
      if (_serverInfoMatchesBaseUrl(serverInfo, current)) {
        matched.add(serverInfo);
      } else {
        others.add(serverInfo);
      }
    }
    return [...matched, ...others];
  }

  bool _serverInfoMatchesBaseUrl(ServerInfoBean serverInfo, String baseUrl) {
    if (baseUrl.isEmpty || baseUrl == ApiController.p2pBaseUrl) return false;
    final urls = <String>[
      (serverInfo.userInputUrl ?? '').trim(),
      _buildLanHttpBaseUrl(serverInfo),
      serverInfo.serverUrl.trim(),
    ];
    for (final rawUrl in urls) {
      if (_normalizeBaseUrl(rawUrl) == baseUrl) {
        return true;
      }
    }
    return false;
  }

  List<String> _buildDirectProbeCandidates(
    List<ServerInfoBean> serverInfos, {
    String? failedBaseUrl,
  }) {
    final failed = _normalizeBaseUrl(failedBaseUrl ?? '');
    final current = _normalizeBaseUrl(baseUrl);
    final privateUrls = <String>[];
    final publicUrls = <String>[];
    final out = <String>[];
    final preferPublicFirst = _shouldPreferPublicDirectUrls();

    void addUrl(String rawUrl) {
      final url = _normalizeBaseUrl(rawUrl);
      if (url.isEmpty) return;
      if (failed.isNotEmpty && url == failed) return;
      if (_isUrlPrivateLan(url)) {
        privateUrls.add(url);
      } else {
        publicUrls.add(url);
      }
    }

    if (current.isNotEmpty &&
        current != ApiController.p2pBaseUrl &&
        !preferPublicFirst) {
      addUrl(current);
    }
    for (final serverInfo in serverInfos) {
      addUrl((serverInfo.userInputUrl ?? '').trim());
      addUrl(_buildLanHttpBaseUrl(serverInfo));
      addUrl(serverInfo.serverUrl.trim());
    }
    if (current.isNotEmpty &&
        current != ApiController.p2pBaseUrl &&
        preferPublicFirst) {
      addUrl(current);
    }
    if (preferPublicFirst) {
      out.addAll(publicUrls);
      out.addAll(privateUrls);
    } else {
      out.addAll(privateUrls);
      out.addAll(publicUrls);
    }
    return out;
  }

  bool _shouldPreferPublicDirectUrls() {
    final active = _globalLastConnectivity
        .where((e) => e != ConnectivityResult.none)
        .toSet();
    if (active.contains(ConnectivityResult.wifi)) return false;
    if (active.contains(ConnectivityResult.mobile)) return true;
    return false;
  }

  bool _isUrlPrivateLan(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return _isPrivateIpv4(uri.host);
  }

  bool _isPrivateIpv4(String host) {
    final parts = host.trim().split('.');
    if (parts.length != 4) return false;
    final nums = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      nums.add(value);
    }
    final a = nums[0];
    final b = nums[1];
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 127) return true;
    return false;
  }

  Future<bool> _switchDevToDirect(
    ServerInfoBean serverInfo, {
    required String expectedServerId,
  }) async {
    final candidates = _buildFailoverCandidates(
      serverInfo,
      failedBaseUrl: ApiController.p2pBaseUrl,
    );
    for (final c in candidates) {
      if (c.isP2p) continue;
      final ok = await _trySwitchToDirect(
        c.baseUrl,
        expectedServerId: expectedServerId,
      );
      if (ok) return true;
    }
    return false;
  }

  Future<bool> _switchDevToP2p(
    ServerInfoBean serverInfo, {
    required String expectedServerId,
    required P2pIcePreference icePreference,
  }) async {
    final code = (serverInfo.pairCode ?? '').trim();
    if (code.isEmpty) return false;

    final previousBaseUrl = baseUrl;
    final previousWasP2p = isP2pMode;

    try {
      await connectP2pByPairCode(
        code,
        icePreference: icePreference,
      ).timeout(const Duration(seconds: 25));
      final ok = await _probeHealthP2p(expectedServerId: expectedServerId);
      if (ok) return true;
    } catch (_) {}

    await disconnectP2p().catchError((_) {});
    if (!previousWasP2p &&
        previousBaseUrl.trim().isNotEmpty &&
        previousBaseUrl.trim() != ApiController.p2pBaseUrl) {
      setBaseUrl(previousBaseUrl);
    }
    return false;
  }

  List<_FailoverCandidate> _buildFailoverCandidates(
    ServerInfoBean serverInfo, {
    required String failedBaseUrl,
  }) {
    final failed = _normalizeBaseUrl(failedBaseUrl);
    final out = <_FailoverCandidate>[];
    final seen = <String>{};

    void addDirect(String url) {
      final n = _normalizeBaseUrl(url);
      if (n.isEmpty) return;
      if (n == failed) return;
      if (seen.add(n)) {
        out.add(_FailoverCandidate(baseUrl: n, isP2p: false));
      }
    }

    final inputUrl = (serverInfo.userInputUrl ?? '').trim();
    final lanUrl = _buildLanHttpBaseUrl(serverInfo);
    final storedUrl = serverInfo.serverUrl.trim();

    if (failed == ApiController.p2pBaseUrl) {
      addDirect(inputUrl);
      addDirect(lanUrl);
      addDirect(storedUrl);
      return out;
    }

    addDirect(inputUrl);
    addDirect(lanUrl);
    addDirect(storedUrl);

    final pairCode = (serverInfo.pairCode ?? '').trim();
    if (pairCode.isNotEmpty && failed != ApiController.p2pBaseUrl) {
      out.add(
        const _FailoverCandidate(
          baseUrl: ApiController.p2pBaseUrl,
          isP2p: true,
        ),
      );
    }

    return out;
  }

  String _normalizeBaseUrl(String url) {
    var s = url.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  String _buildLanHttpBaseUrl(ServerInfoBean serverInfo) {
    final ip = (serverInfo.lanIpv4 ?? '').trim();
    final portRaw = (serverInfo.lanHttpPort ?? '').trim();
    if (ip.isEmpty || portRaw.isEmpty) return '';
    final port = int.tryParse(portRaw);
    if (port == null || port <= 0 || port > 65535) return '';

    final ref = (serverInfo.userInputUrl ?? '').trim().isNotEmpty
        ? serverInfo.userInputUrl!.trim()
        : serverInfo.serverUrl.trim();
    final uri = Uri.tryParse(ref);
    final scheme = (uri != null && uri.scheme.trim().isNotEmpty)
        ? uri.scheme.trim()
        : 'http';
    return '$scheme://$ip:$port';
  }

  /// 快速分享等「本地链接」展示用 HTTP 根地址。P2P 时 API 的 [baseUrl] 为占位符 [p2pBaseUrl]，
  /// Web 端用浏览器地址栏 origin，非 Web 用当前服务器局域网 IP + HTTP 端口（与存储的服务器信息一致）。
  String quickShareLocalHttpOrigin() {
    final current = baseUrl.trim();
    if (current != ApiController.p2pBaseUrl) {
      return _normalizeBaseUrl(current);
    }
    if (kIsWeb) {
      return '${Uri.base.scheme}://${Uri.base.authority}';
    }
    final serverId = _state.serverId.trim();
    if (serverId.isEmpty) return current;
    final infos = _orderServerInfosForCurrentBaseUrl(
      _loadServerInfosById(serverId),
    );
    if (infos.isEmpty) return current;
    final info = infos.first;
    final lan = _buildLanHttpBaseUrl(info).trim();
    if (lan.isNotEmpty) return _normalizeBaseUrl(lan);
    final raw = (info.userInputUrl ?? '').trim().isNotEmpty
        ? info.userInputUrl!.trim()
        : info.serverUrl.trim();
    final fallback = _normalizeBaseUrl(raw);
    return fallback.isNotEmpty ? fallback : current;
  }

  Future<bool> _trySwitchToDirect(
    String baseUrl, {
    required String expectedServerId,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) return false;
    if (!_isValidHttpBaseUrl(normalized)) return false;
    if (normalized == _normalizeBaseUrl(this.baseUrl)) return false;

    final ok = await _probeHealthDirect(
      normalized,
      expectedServerId: expectedServerId,
    );
    if (!ok) return false;

    final wasP2p = isP2pMode;
    setBaseUrl(normalized);
    if (wasP2p) {
      unawaited(_disconnectP2pIfNotInUse());
    }
    return true;
  }

  Future<void> _disconnectP2pIfNotInUse() async {
    await Future.delayed(const Duration(seconds: 2));
    if (isP2pMode) return;
    await disconnectP2p().catchError((_) {});
  }

  Future<bool> _trySwitchToP2p(
    ServerInfoBean serverInfo, {
    required String expectedServerId,
  }) async {
    final code = (serverInfo.pairCode ?? '').trim();
    if (code.isEmpty) return false;

    final previousBaseUrl = baseUrl;
    final previousWasP2p = isP2pMode;

    try {
      print('🟡 [Failover] 尝试 P2P 自动模式: pairCode=$code');
      await connectP2pByPairCode(
        code,
        icePreference: P2pIcePreference.auto,
      ).timeout(const Duration(seconds: 25));
      final ok = await _probeHealthP2p(expectedServerId: expectedServerId);
      if (ok) {
        // 自动模式连接成功；若落在中继，后台尝试升级为直连
        scheduleP2pDirectUpgrade();
        return true;
      }
    } catch (_) {}

    await disconnectP2p().catchError((_) {});
    if (!previousWasP2p &&
        previousBaseUrl.trim().isNotEmpty &&
        previousBaseUrl.trim() != ApiController.p2pBaseUrl) {
      setBaseUrl(previousBaseUrl);
    }
    return false;
  }

  bool _isValidHttpBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;
    if (!uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (!uri.hasAuthority) return false;
    return true;
  }

  // ── 全局网络类型变化监控 ─────────────────────────────────────────────────────
  //
  // 目的：当设备网络类型发生切换（如 WiFi → 5G），主动按优先级探测所有可用通道：
  //   ip直连 > p2p打洞直连 > p2p中继
  // 而不是等请求失败后再被动触发 failover。

  /// 启动全局网络类型变化监控。在用户登录后调用，登出时停止。
  Future<void> startGlobalNetworkMonitor() async {
    if (kIsWeb) return;
    if (_globalNetMonitorSub != null) return;
    final connectivity = Connectivity();
    try {
      _globalLastConnectivity = List.unmodifiable(
        await connectivity.checkConnectivity(),
      );
      print('🟢 [NetMonitor] 初始网络基线: $_globalLastConnectivity');
    } catch (e) {
      _globalLastConnectivity = const [];
      print('🔴 [NetMonitor] 获取初始网络基线失败: $e');
    }
    _globalNetMonitorSub = connectivity.onConnectivityChanged.listen(
      _onGlobalConnectivityChanged,
    );
  }

  /// 停止全局网络类型变化监控。
  void stopGlobalNetworkMonitor() {
    try {
      _globalNetChangeProbeTimer?.cancel();
    } catch (_) {}
    _globalNetChangeProbeTimer = null;
    try {
      _globalNetMonitorSub?.cancel();
    } catch (_) {}
    _globalNetMonitorSub = null;
    _globalLastConnectivity = const [];
    _globalNetChangeProbeLocked = false;
    _globalNetChangeProbeMsAt = 0;
  }

  void _onGlobalConnectivityChanged(List<ConnectivityResult> results) {
    final prev = _globalLastConnectivity;
    _globalLastConnectivity = List.unmodifiable(results);

    if (!isAuthenticated) return;

    final newActive = results
        .where((e) => e != ConnectivityResult.none)
        .toSet();
    if (newActive.isEmpty) return;

    final prevActive = prev.where((e) => e != ConnectivityResult.none).toSet();
    if (prevActive == newActive) return;

    print('🟡 [NetMonitor] 网络类型变化: $prevActive -> $newActive');
    _scheduleGlobalNetChangeProbeDebounced();
  }

  void _scheduleGlobalNetChangeProbeDebounced({
    Duration delay = const Duration(milliseconds: 800),
  }) {
    try {
      _globalNetChangeProbeTimer?.cancel();
    } catch (_) {}
    _globalNetChangeProbeTimer = Timer(
      delay,
      () => unawaited(_runFullChannelProbeAfterNetworkChange()),
    );
  }

  /// 网络类型切换后，按优先级（ip直连 > p2p直连 > p2p中继）全量探测所有通道，
  /// 自动切换到最高优先级的可用连接。
  Future<void> _runFullChannelProbeAfterNetworkChange() async {
    if (kIsWeb) return;
    if (!isAuthenticated) return;
    if (_globalNetChangeProbeLocked) {
      print('🟡 [NetMonitor] 上一次重检仍在进行，稍后重试');
      _scheduleGlobalNetChangeProbeDebounced(delay: const Duration(seconds: 2));
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = nowMs - _globalNetChangeProbeMsAt;
    if (elapsedMs < 5000) {
      final retryDelayMs = 5000 - elapsedMs + 100;
      print('🟡 [NetMonitor] 重检节流中，${retryDelayMs}ms 后重试');
      _scheduleGlobalNetChangeProbeDebounced(
        delay: Duration(milliseconds: retryDelayMs),
      );
      return;
    }
    _globalNetChangeProbeMsAt = nowMs;

    final serverId = _state.serverId.trim();
    if (serverId.isEmpty) return;

    final serverInfos = _loadServerInfosById(serverId);
    if (serverInfos.isEmpty) return;

    _globalNetChangeProbeLocked = true;

    _failoverCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      print('🟡 [NetMonitor] 开始执行网络变化后的连接重检');
      await _probePreferredChannel(
        serverInfos,
        expectedServerId: serverId,
        reconnectCurrentP2p: false,
      );
    } finally {
      _globalNetChangeProbeLocked = false;
    }
  }

  Future<bool> _probeHealthDirect(
    String baseUrl, {
    required String expectedServerId,
  }) async {
    final uri = Uri.tryParse('${_normalizeBaseUrl(baseUrl)}/health');
    if (uri == null) return false;

    final client = createHttpClient();
    final timeout =
        _shouldPreferPublicDirectUrls() && !_isUrlPrivateLan(baseUrl)
        ? const Duration(seconds: 4)
        : ApiController._failoverProbeTimeout;
    try {
      final res = await client.get(uri).timeout(timeout);
      if (res.statusCode != 200) return false;
      final json = _tryDecodeJsonMap(res.body);
      if (json == null) return false;
      return _isHealthOk(json, expectedServerId: expectedServerId);
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _probeHealthP2p({required String expectedServerId}) async {
    if (!isP2pReady) return false;
    final uri = Uri.tryParse(
      '${_normalizeBaseUrl(ApiController.p2pBaseUrl)}/health',
    );
    if (uri == null) return false;
    try {
      final req = http.Request('GET', uri);
      final streamed = await sendP2pRequest(
        req,
        timeout: ApiController._failoverProbeTimeout,
      );
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode != 200) return false;
      final json = _tryDecodeJsonMap(res.body);
      if (json == null) return false;
      return _isHealthOk(json, expectedServerId: expectedServerId);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  bool _isHealthOk(
    Map<String, dynamic> json, {
    required String expectedServerId,
  }) {
    final successRaw = json['success'];
    final success =
        successRaw == true ||
        successRaw == 1 ||
        (successRaw != null && successRaw.toString().toLowerCase() == 'true');
    if (!success) return false;

    final expected = expectedServerId.trim();
    if (expected.isEmpty) return true;

    final sid = (json['serverId']?.toString() ?? '').trim();
    if (sid.isEmpty) return true;
    return sid == expected;
  }
}
