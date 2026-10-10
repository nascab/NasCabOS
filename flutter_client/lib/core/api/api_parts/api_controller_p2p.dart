part of '../api_controller.dart';

extension ApiControllerP2p on ApiController {
  Future<Map<String, String>> getP2pTransportStats() async {
    final rtc = _p2pRtc;
    if (rtc == null) return {};
    try {
      return await rtc.getTransportStats();
    } catch (_) {
      return {};
    }
  }

  String _getStoredP2pPairCode() {
    try {
      return (CacheManager().getString(CacheKeys.p2pLastPairCode) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  bool _isP2pReconnectableError(Object e) {
    final s = e.toString();
    return s.contains('p2p_not_connected') ||
        s.contains('p2p_disconnected') ||
        s.contains('p2p_dc_closed') ||
        s.contains('p2p_dc_error') ||
        s.contains('p2p_ws_error') ||
        s.contains('p2p_ws_closed') ||
        s.contains('p2p_dc_not_open') ||
        // rtc close()（含 pc Failed 触发的清理）会以 p2p_closed 失败所有在途请求
        s.contains('p2p_closed');
  }

  /// 检查主 P2P 连接（API 数据通道）是否真的还活着。
  ///
  /// 用于重连前的健康检测：单主连接策略下，API 通道仍 open 时跳过
  /// _forceReconnectP2p，避免无谓中断并重复 session/create。
  bool _isMainP2pConnectionAlive() {
    if (!isP2pReady) return false;
    final rtc = _p2pRtc;
    if (rtc == null) return false;
    return rtc.isApiChannelOpen;
  }

  /// 主连接上是否有进行中的 P2P 请求（含流式下载/上传体）。
  bool _anyP2pRtcHasPendingRequests() {
    try {
      if (_p2pRtc?.hasPendingRequests == true) return true;
    } catch (_) {}
    return false;
  }

  bool _isP2pAutoMode() {
    return _devConnectMode == DevConnectMode.auto;
  }

  bool _shouldAutoUpgradeRelayToDirect() {
    if (kIsWeb) return false;
    if (!_isP2pAutoMode()) return false;
    if (!isP2pMode) return false;
    if (!isP2pReady) return false;
    if (_p2pTransportKind != P2pTransportKind.relay) return false;
    if (_p2pActiveIcePreference != P2pIcePreference.auto) return false;
    if (_p2pIcePreference != P2pIcePreference.auto) return false;
    return true;
  }

  void _resetP2pAutoSwitchState() {
    _p2pAutoSwitchInProgress = false;
    _p2pLastAutoSwitchAttemptAtMs = 0;
    _p2pLastAutoSwitchProbeAtMs = 0;
  }

  Future<void> _runP2pAutoSwitchProbe({
    bool ignoreProbeThrottle = false,
  }) async {
    if (!_shouldAutoUpgradeRelayToDirect()) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!ignoreProbeThrottle && nowMs - _p2pLastAutoSwitchProbeAtMs < 10000) {
      return;
    }
    _p2pLastAutoSwitchProbeAtMs = nowMs;
    await _attemptUpgradeRelayToDirect();
  }

  Future<void> _attemptUpgradeRelayToDirect() async {
    if (!_shouldAutoUpgradeRelayToDirect()) return;
    if (_p2pAutoSwitchInProgress) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _p2pLastAutoSwitchAttemptAtMs < 20000) return;
    _p2pLastAutoSwitchAttemptAtMs = nowMs;

    // 有 in-flight 请求时跳过，避免中断正在进行的 API 调用
    // 下一次定期探测（60s 后）或网络变化时会再次触发
    if (_anyP2pRtcHasPendingRequests()) return;

    final code = _p2pPairCode.trim().isNotEmpty
        ? _p2pPairCode.trim()
        : _getStoredP2pPairCode();
    if (code.isEmpty) return;

    _p2pAutoSwitchInProgress = true;
    final previousIcePreference = _p2pIcePreference;
    try {
      await connectP2pByPairCode(
        code,
        icePreference: P2pIcePreference.directOnly,
        resetReconnectAttempts: false,
      ).timeout(const Duration(seconds: 25));

      await Future<void>.delayed(const Duration(milliseconds: 650));
      final stats = await getP2pTransportStats();
      final type = (stats['type'] ?? '').trim().toLowerCase();
      if (type == 'relay' || type.isEmpty) {
        throw Exception('p2p_direct_not_available');
      }
      _p2pTransportKind = P2pTransportKind.direct;
      _bumpConnectChannelRevision();
    } catch (_) {
      try {
        await connectP2pByPairCode(
          code,
          icePreference: P2pIcePreference.auto,
          resetReconnectAttempts: false,
        ).timeout(const Duration(seconds: 25));
      } catch (_) {}
    } finally {
      if (_isP2pAutoMode()) {
        if (previousIcePreference == P2pIcePreference.auto) {
          _p2pIcePreference = P2pIcePreference.auto;
          _p2pActiveIcePreference = P2pIcePreference.auto;
        }
      }
      _p2pAutoSwitchInProgress = false;
    }
  }

  /// 登录后调用：若当前 P2P 走的是中继，后台探测直连并尝试升级为直连。
  ///
  /// 连接成功后约 800ms 才会异步确认 transport kind，因此延迟一点再触发，
  /// 确保 [P2pTransportKind.relay] 状态已就绪。
  void scheduleP2pDirectUpgrade() {
    unawaited(
      Future.delayed(const Duration(milliseconds: 1500), () async {
        await _runP2pAutoSwitchProbe(ignoreProbeThrottle: true);
      }),
    );
  }

  Future<bool> ensureP2pConnected({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!isP2pMode) return isP2pReady;
    if (isP2pReady) return true;
    final code = _getStoredP2pPairCode();
    if (code.isEmpty) return false;

    if (_p2pChannel != null && !isP2pReady) {
      try {
        await onP2pReadyChanged.firstWhere((ready) => ready).timeout(timeout);
        return isP2pReady;
      } catch (_) {}
    }

    if (_p2pReconnectTimer != null || _isP2pConnectCooldownActive()) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final remainingMs = _p2pNextConnectAllowedAtMs - nowMs;
      final waitMs = remainingMs > 1000
          ? 1000
          : (remainingMs > 0 ? remainingMs : 1000);
      try {
        await onP2pReadyChanged
            .firstWhere((ready) => ready)
            .timeout(Duration(milliseconds: waitMs));
        return isP2pReady;
      } catch (_) {}
      return isP2pReady;
    }

    try {
      await connectP2pByPairCode(
        code,
        resetReconnectAttempts: false,
      ).timeout(timeout);
    } catch (_) {}
    return isP2pReady;
  }

  Future<bool> forceReconnectP2p({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return _forceReconnectP2p(timeout: timeout);
  }

  Future<bool> _forceReconnectP2p({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final inFlight = _p2pReconnectInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final task = _forceReconnectP2pLocked(timeout: timeout);
    _p2pReconnectInFlight = task;
    return task.whenComplete(() {
      if (identical(_p2pReconnectInFlight, task)) {
        _p2pReconnectInFlight = null;
      }
    });
  }

  Future<bool> _forceReconnectP2pLocked({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!isP2pMode) return false;
    final code = _getStoredP2pPairCode();
    if (code.isEmpty) return false;
    try {
      await _cleanupP2p(disableReconnect: false);
    } catch (_) {}
    try {
      await connectP2pByPairCode(code).timeout(timeout);
    } catch (_) {}
    return isP2pReady;
  }

  Future<void> _cleanupP2p({
    required bool disableReconnect,
    int? expectedConnectToken,
  }) async {
    if (expectedConnectToken != null &&
        expectedConnectToken != _p2pConnectToken) {
      return;
    }
    _resetP2pAutoSwitchState();
    _setP2pReady(false);
    _p2pSessionId = '';
    _p2pTransportKind = P2pTransportKind.unknown;
    _p2pRelayAddress = '';
    _bumpConnectChannelRevision();
    _p2pActiveIcePreference = P2pIcePreference.auto;
    if (disableReconnect) {
      _p2pAllowReconnect = false;
      _p2pLastPairCode = '';
      _p2pReconnectAttempts = 0;
      _p2pNextConnectAllowedAtMs = 0;
      try {
        _p2pReconnectTimer?.cancel();
      } catch (_) {}
      _p2pReconnectTimer = null;
      _p2pPairCode = '';
    }
    _p2pIceServers = const [];
    try {
      _p2pWsHeartbeatTimer?.cancel();
    } catch (_) {}
    _p2pWsHeartbeatTimer = null;
    try {
      await _p2pRtc?.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _p2pRtc = null;
    try {
      await _p2pSub?.cancel();
    } catch (_) {}
    _p2pSub = null;
    try {
      _p2pChannel?.sink.close();
    } catch (_) {}
    _p2pChannel = null;
  }

  /// P2P 链路意外断开（WS error/session:closed/onDone、pc Failed/Closed）的统一收尾：
  /// 去重后清理资源并按退避调度重连。多个断开信号（如 pc Failed 与 WS onDone
  /// 几乎同时到达）由防重入标志与 token 校验去重，避免重复清理/重复调度。
  Future<void> _handleP2pConnectionLost(int expectedToken, Object error) async {
    if (expectedToken != _p2pConnectToken) return;
    if (_p2pConnectionLostHandling) return;
    _p2pConnectionLostHandling = true;
    try {
      _p2pLastConnectError = error;
      await _cleanupP2p(
        disableReconnect: false,
        expectedConnectToken: expectedToken,
      );
      _scheduleP2pReconnect();
    } finally {
      _p2pConnectionLostHandling = false;
    }
  }

  void _scheduleP2pReconnect() {
    if (!_p2pAllowReconnect) return;
    final code = _p2pLastPairCode.trim();
    if (code.isEmpty) return;
    if (_p2pReconnectTimer != null) return;

    final lastErrorText = _p2pLastConnectError?.toString().toLowerCase() ?? '';
    if (lastErrorText.contains('pair_session_http_410')) {
      // 会话已被服务端终结（HTTP 410 Gone，如会话失效/被顶替）：
      // 自动重连大概率再次失败或形成两端互踢，停止后台重试，等待用户手动重连
      print('🔴 [P2pReconnect] pair_session_http_410，停止自动重连');
      _p2pAllowReconnect = false;
      _emitConnectionState('failed');
      return;
    }

    final attempt = _p2pReconnectAttempts;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var seconds = _nextP2pReconnectDelaySeconds(_p2pLastConnectError);
    _p2pReconnectAttempts = attempt + 1;
    _p2pNextConnectAllowedAtMs = nowMs + seconds * 1000;

    _p2pReconnectTimer = Timer(Duration(seconds: seconds), () async {
      _p2pReconnectTimer = null;
      _emitConnectionState('reconnecting');
      try {
        await connectP2pByPairCode(code, resetReconnectAttempts: false);
        _p2pReconnectAttempts = 0;
      } catch (_) {
        _scheduleP2pReconnect();
      }
    });
  }

  bool _isP2pConnectCooldownActive() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return nowMs < _p2pNextConnectAllowedAtMs;
  }

  int _nextP2pReconnectDelaySeconds(Object? error) {
    final s = error?.toString().toLowerCase() ?? '';
    if (s.contains('pair_session_http_404') ||
        s.contains('pair_session_http_403')) {
      // 信令侧失败（服务器离线/鉴权失败）：15s 起指数退避至 120s 上限，
      // 避免固定 15s 高频重试持续打到信令服务器（410 在调度入口直接停止重连）
      final attempt = _p2pReconnectAttempts;
      final exp = attempt > 3 ? 3 : attempt;
      final baseSeconds = 15 * (1 << exp); // 15 / 30 / 60 / 120
      final clampedBase = baseSeconds > 120 ? 120 : baseSeconds;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final jitterFactor = 0.8 + (nowMs % 400) / 1000.0;
      var seconds = (clampedBase * jitterFactor).round();
      if (seconds < 15) seconds = 15;
      return seconds;
    }

    final attempt = _p2pReconnectAttempts;
    final exp = attempt > 5 ? 5 : attempt;
    final baseSeconds = 2 * (1 << exp);
    final clampedBase = baseSeconds > 30 ? 30 : baseSeconds;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final jitterFactor = 0.8 + (nowMs % 400) / 1000.0;
    var seconds = (clampedBase * jitterFactor).round();
    if (seconds < 1) seconds = 1;
    return seconds;
  }

  Future<void> disconnectP2p() async {
    // 先同步递增 token，立即作废在途建连尝试（覆盖 session/create HTTP 窗口：
    // 此时 _p2pChannel 尚未赋值、isP2pEnabled=false，attempt 无法被外部在途
    // 检测发现，断开后继续执行会建立用户已断开的僵尸连接）。attempt 在各
    // 检查点发现 token 失效后会自行清理退出；此处再立即清理当前已有资源，
    // 与 attempt 收尾清理的并发由 _cleanupP2p 的幂等性（全量 try-catch）兜底。
    _p2pConnectToken++;
    await _cleanupP2p(disableReconnect: true);
  }

  Future<void> connectP2pByPairCode(
    String pairCode, {
    P2pIcePreference? icePreference,
    bool resetReconnectAttempts = true,
  }) {
    final code = pairCode.trim();
    if (icePreference != null) {
      _p2pIcePreference = icePreference;
      _p2pTransportKind = icePreference == P2pIcePreference.relayOnly
          ? P2pTransportKind.relay
          : (icePreference == P2pIcePreference.directOnly
                ? P2pTransportKind.direct
                : P2pTransportKind.unknown);
      _bumpConnectChannelRevision();
    } else {
      // 恢复为开发连接模式对应的 ICE 偏好（非 Debug 恒为 auto）。
      // `_p2pIcePreference` 会被运行时改写（relay fallback、directOnly 升级探测），
      // 裸重连（自动重连/网络变化重检）直接沿用残留值会导致实际路径与
      // 用户设置脱节（如强制中继模式实际直连、连接通道 UI 显示错误）
      final P2pIcePreference restored;
      switch (_devConnectMode) {
        case DevConnectMode.p2pDirect:
          restored = P2pIcePreference.directOnly;
        case DevConnectMode.p2pRelay:
          restored = P2pIcePreference.relayOnly;
        default:
          restored = P2pIcePreference.auto;
      }
      _p2pIcePreference = restored;
      _p2pTransportKind = restored == P2pIcePreference.relayOnly
          ? P2pTransportKind.relay
          : P2pTransportKind.unknown;
      _bumpConnectChannelRevision();
    }
    if (resetReconnectAttempts) {
      _p2pReconnectAttempts = 0;
      try {
        _p2pReconnectTimer?.cancel();
      } catch (_) {}
      _p2pReconnectTimer = null;
    }
    // 入口同步标记建连意图（含队列排队阶段），供在途检测覆盖
    // session/create HTTP 窗口（_p2pChannel 尚未赋值、isP2pEnabled=false 的盲区）
    _p2pConnectingPairCode = code;
    final task = _p2pConnectQueue.then(
      (_) => _connectP2pByPairCodeLocked(
        code,
        resetReconnectAttempts: resetReconnectAttempts,
      ),
    );
    _p2pConnectQueue = task.catchError((_) {});
    return task.whenComplete(() {
      // 仅当没有更新的建连意图覆盖时清除（同码重连会再次写入同值）
      if (_p2pConnectingPairCode == code) {
        _p2pConnectingPairCode = null;
      }
    });
  }

  Future<ServerStatusResponse> connectP2pByPairCodeAndCheckServerStatus(
    String pairCode, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    print(
      '🔵 [P2pCheck] 开始 connectP2pByPairCodeAndCheckServerStatus, 配对码长度: ${pairCode.length}',
    );
    print('🔵 [P2pCheck] 步骤1: 调用 connectP2pByPairCode...');
    await connectP2pByPairCode(pairCode);
    print(
      '🔵 [P2pCheck] 步骤2: connectP2pByPairCode 完成, 调用 checkServerStatus...',
    );
    final result = AuthApiService.instance.checkServerStatus(
      false,
      timeout: timeout,
    );
    print('🔵 [P2pCheck] checkServerStatus 调用完成');
    return result;
  }

  Future<void> _connectP2pByPairCodeLocked(
    String code, {
    required bool resetReconnectAttempts,
  }) async {
    // auto 偏好下打洞失败时，由 attempt 内部立即以 relayOnly 回退重连一次，
    // 避免进入「20s 打洞超时 → 退避重连 → 再打洞失败」的长时间循环
    await _connectP2pByPairCodeAttempt(
      code,
      resetReconnectAttempts: resetReconnectAttempts,
    );
  }

  Future<void> _connectP2pByPairCodeAttempt(
    String code, {
    required bool resetReconnectAttempts,
    bool allowRelayFallback = true,
  }) async {
    print(
      '🟡 [P2pConnect] 开始连接, 配对码: "$code", resetReconnectAttempts: $resetReconnectAttempts',
    );
    if (code.isEmpty) {
      print('🔴 [P2pConnect] 配对码为空');
      throw Exception('pair_code_empty');
    }

    if (isP2pEnabled &&
        _p2pReady &&
        _p2pPairCode.trim() == code &&
        _p2pActiveIcePreference == _p2pIcePreference) {
      print('🟡 [P2pConnect] 已存在相同连接，直接返回');
      return;
    }

    _p2pAllowReconnect = true;
    _p2pLastPairCode = code;
    try {
      _p2pReconnectTimer?.cancel();
    } catch (_) {}
    _p2pReconnectTimer = null;

    if (resetReconnectAttempts) {
      _emitConnectionState('connecting');
    }

    final previousBaseUrl = baseUrl;
    final connectToken = ++_p2pConnectToken;
    bool isCurrentConnectToken() => connectToken == _p2pConnectToken;
    // 中继回退递归会递增 token：外层 catch 需据此区分「被递归接管」与
    // 「被 disconnect 作废」，避免误清递归已调度的重连
    var relayFallbackStarted = false;

    try {
      print('🟡 [P2pConnect] 清理旧连接...');
      await _cleanupP2p(
        disableReconnect: false,
        expectedConnectToken: connectToken,
      );
      if (kIsWeb) {
        // Web 端 WebsocketChannel 关闭异步完成，短暂让步后再重建；
        // 250ms 过长，50ms 已足够避免新旧连接争抢
        await Future.delayed(const Duration(milliseconds: 50));
      }
      print('🟡 [P2pConnect] 调用 _createP2pSession...');
      final session = await _createP2pSession(code);
      if (!isCurrentConnectToken()) {
        // disconnect 已在 session/create 窗口作废本次建连意图：
        // 立即中止，不再建立 WS/RTC（否则形成用户已断开的僵尸连接）
        print('🔴 [P2pConnect] 建连意图已作废（session/create 期间断开），中止');
        throw Exception('p2p_connect_cancelled');
      }

      final wsUrl = (session['wsUrl']?.toString() ?? '').trim();
      final sessionId = (session['sessionId']?.toString() ?? '').trim();
      print('🟡 [P2pConnect] 会话返回: wsUrl="$wsUrl", sessionId="$sessionId"');
      if (wsUrl.isEmpty || sessionId.isEmpty) {
        print('🔴 [P2pConnect] wsUrl 或 sessionId 为空');
        throw Exception('pair_session_invalid');
      }

      final uri = Uri.tryParse(wsUrl);
      if (uri == null) {
        print('🔴 [P2pConnect] wsUrl 解析失败');
        throw Exception('pair_ws_url_invalid');
      }
      print('🟡 [P2pConnect] WebSocket URI: $uri');

      if (kIsWeb) {
        _p2pChannel = p2p_ws_factory.createP2pWebSocketChannel(uri, null);
      } else {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        _p2pChannel = p2p_ws_factory.createP2pWebSocketChannel(uri, client);
      }
      print('🟡 [P2pConnect] WebSocket 已创建，等待 session:ready...');
      _p2pSessionId = sessionId;
      _p2pPairCode = code;
      setBaseUrl(ApiController.p2pBaseUrl);

      _p2pWsHeartbeatTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        final ch = _p2pChannel;
        if (ch == null) return;
        try {
          final bytes = encodeSignaling({
            'type': 'ping',
            'ts': DateTime.now().millisecondsSinceEpoch,
          });
          if (bytes != null) ch.sink.add(bytes);
        } catch (_) {}
      });

      final ready = Completer<void>();

      // 建议 5：HTTP 返回即预热 PC —— session/create 响应已带 iceServers
      // （与 WS session:ready 下发的同源：均来自信令服务的会话 ticket）。
      // 先建 PC + attach 通道 + createOffer + setLocalDescription（ICE gather
      // 提前启动），与 WS 建连并行；offer 发送等 session:ready（readySignal）。
      // session:ready 到达时深比较两份 iceServers，不一致则废弃预热退回旧路径
      List<dynamic>? prewarmedIce;
      var prewarmIceMatched = false;
      final sessionIceRaw = session['iceServers'];
      if (sessionIceRaw is List && sessionIceRaw.isNotEmpty) {
        try {
          prewarmedIce = _applyIcePreference(sessionIceRaw, _p2pIcePreference);
        } catch (_) {
          // 如 relayOnly 但响应无 TURN：预热不可用，退回旧路径（会抛同错误）
          prewarmedIce = null;
        }
      }
      P2pRtcClient? prewarmRtc;
      Future<void>? prewarmStart;
      if (prewarmedIce != null) {
        try {
          final prewarmChannel = _p2pChannel!;
          _p2pRelayAddress = _extractTurnServerAddress(prewarmedIce);
          _bumpConnectChannelRevision();
          final rtcClient = P2pRtcClient(
            sessionId: sessionId,
            iceServers: prewarmedIce,
            iceTransportPolicy: _p2pIcePreference == P2pIcePreference.relayOnly
                ? 'relay'
                : null,
            directOnly: _p2pIcePreference == P2pIcePreference.directOnly,
            sendWsJson: (payload) {
              try {
                final bytes = encodeSignaling(payload);
                if (bytes != null) prewarmChannel.sink.add(bytes);
              } catch (_) {}
            },
          );
          _p2pRtc = rtcClient;
          // pc Failed/Closed（非本端主动关闭）时通知 controller 清理并调度重连：
          // 此前 rtc 内部直接 close 不上报，链路死亡后上层无感知（假在线直到请求超时）
          rtcClient.onConnectionLost = () {
            if (!isCurrentConnectToken()) return;
            if (!identical(_p2pRtc, rtcClient)) return;
            unawaited(
              _handleP2pConnectionLost(
                connectToken,
                Exception('p2p_rtc_connection_lost'),
              ),
            );
          };
          prewarmRtc = rtcClient;
          print('🟡 [P2pConnect] 预热 PC 启动（与 WS 建连并行）...');
          prewarmStart = rtcClient.start(
            channels: const <P2pRtcChannel>[
              P2pRtcChannel.api,
              P2pRtcChannel.file,
              // 与独立 upload/download link 复用同一 PeerConnection，避免二次 ICE/信令在中继下超时
              P2pRtcChannel.upload,
              P2pRtcChannel.download,
              // 让视频播放优先复用主连接，避免额外创建 video link 会话
              P2pRtcChannel.video,
            ],
            readySignal: ready.future,
          );
          // 防孤立异常：废弃/失败路径不再 await 此 future（命中路径 await 派生 future）
          prewarmStart.ignore();
        } catch (e) {
          print('🟠 [P2pConnect] 预热创建失败，退回 ready 后建连: $e');
          prewarmRtc = null;
          prewarmStart = null;
          try {
            await _p2pRtc?.close().timeout(const Duration(seconds: 3));
          } catch (_) {}
          _p2pRtc = null;
        }
      }

      _p2pSub = _p2pChannel!.stream.listen(
        (event) {
          if (!isCurrentConnectToken()) return;
          final msg = decodeSignalingFromEvent(event);
          if (msg == null) {
            print('🟡 [P2pConnect] WebSocket 收到空消息');
            return;
          }

          final type = msg['type']?.toString() ?? '';
          // print('🟡 [P2pConnect] WebSocket 收到消息 type: $type');
          if (type == 'pong') {
            return;
          }
          if (type.startsWith('webrtc:')) {
            _p2pRtc?.handleWsMessage(msg);
            return;
          }
          if (type == 'error') {
            final code =
                msg['code']?.toString() ??
                msg['errorCode']?.toString() ??
                'P2P_ERROR';
            print('🔴 [P2pConnect] WebSocket error: code=$code, msg=$msg');
            if (!ready.isCompleted) {
              ready.completeError(Exception('p2p_ws_error_$code'));
            }
            unawaited(
              _handleP2pConnectionLost(
                connectToken,
                Exception('p2p_ws_error_$code'),
              ),
            );
            return;
          }
          if (type == 'session:ready') {
            print('🟢 [P2pConnect] session:ready 收到, msg=$msg');
            final sid = msg['sessionId']?.toString() ?? '';
            if (sid.isNotEmpty) _p2pSessionId = sid;
            final iceRaw = msg['iceServers'];
            try {
              if (iceRaw is List) {
                _p2pIceServers = _applyIcePreference(iceRaw, _p2pIcePreference);
                print(
                  '🟢 [P2pConnect] ICE Servers 数量: ${_p2pIceServers.length}',
                );
              } else {
                _p2pIceServers = const [];
                print('🟢 [P2pConnect] 无 ICE Servers');
              }
            } catch (e) {
              print('🔴 [P2pConnect] 处理 ICE Servers 失败: $e');
              if (!ready.isCompleted) {
                ready.completeError(e);
              }
              unawaited(_handleP2pConnectionLost(connectToken, e));
              return;
            }
            // 建议 5：与预热用的 HTTP iceServers 深比较（同源时必相等）；
            // 不一致（TURN 凭据轮换等极端情形）则废弃预热 PC，退回旧路径重建
            if (prewarmRtc != null) {
              prewarmIceMatched = _iceServersDeepEqual(
                _p2pIceServers,
                prewarmedIce,
              );
              if (!prewarmIceMatched) {
                print('🟠 [P2pConnect] session:ready ICE 与预热不一致，废弃预热 PC');
                final stale = prewarmRtc;
                prewarmRtc = null;
                _p2pRtc = null;
                unawaited(stale?.close());
              }
            }
            print('🟢 [P2pConnect] ready.complete() 被调用');
            if (!ready.isCompleted) ready.complete();
            return;
          }
          if (type == 'session:closed') {
            print('🔴 [P2pConnect] session:closed 收到');
            if (!ready.isCompleted) {
              ready.completeError(Exception('p2p_session_closed'));
            }
            // 记录错误供退避计算使用（此前未设置，退避只能按 null 走 2s 起步）
            unawaited(
              _handleP2pConnectionLost(
                connectToken,
                Exception('p2p_session_closed'),
              ),
            );
            return;
          }
        },
        onError: (e) {
          print('🔴 [P2pConnect] WebSocket onError: $e');
          // 先解除 ready 等待（即使 token 已失效，也要让在途 attempt 尽快
          // 走到检查点自行中止），再走统一断连收尾
          if (!ready.isCompleted) {
            ready.completeError(Exception('p2p_ws_error'));
          }
          if (!isCurrentConnectToken()) return;
          unawaited(
            _handleP2pConnectionLost(connectToken, Exception('p2p_ws_error')),
          );
        },
        onDone: () {
          print('🔴 [P2pConnect] WebSocket onDone (closed)');
          if (!ready.isCompleted) {
            ready.completeError(Exception('p2p_ws_closed'));
          }
          if (!isCurrentConnectToken()) return;
          unawaited(
            _handleP2pConnectionLost(connectToken, Exception('p2p_ws_closed')),
          );
        },
        cancelOnError: false,
      );

      print('🟡 [P2pConnect] 等待 session:ready (超时 20s)...');
      await ready.future.timeout(const Duration(seconds: 20));
      if (!isCurrentConnectToken()) {
        throw Exception('p2p_connect_replaced');
      }
      print('🟢 [P2pConnect] session:ready 已收到，继续初始化 RTC...');

      final channel = _p2pChannel;
      final sid = _p2pSessionId.trim();
      if (channel == null || sid.isEmpty) {
        print('🔴 [P2pConnect] channel 或 sid 为空');
        throw Exception('p2p_not_connected');
      }
      try {
        if (prewarmRtc != null && prewarmStart != null && prewarmIceMatched) {
          // 建议 5 命中：PC/通道/offer 早已就绪（readySignal 放行后 offer 已发出），
          // 这里只等 api 通道握手（answer → dc open → api:ready）
          _p2pRelayAddress = _extractTurnServerAddress(_p2pIceServers);
          print('🟢 [P2pConnect] 复用预热 RTC，等待 api 通道就绪...');
          await prewarmStart.timeout(const Duration(seconds: 10));
        } else {
          _p2pRelayAddress = _extractTurnServerAddress(_p2pIceServers);
          print(
            '🟡 [P2pConnect] 初始化 P2pRtcClient, sessionId=$sid, relayAddress=$_p2pRelayAddress',
          );
          _bumpConnectChannelRevision();
          final rtcClient = P2pRtcClient(
            sessionId: sid,
            iceServers: _p2pIceServers,
            iceTransportPolicy: _p2pIcePreference == P2pIcePreference.relayOnly
                ? 'relay'
                : null,
            directOnly: _p2pIcePreference == P2pIcePreference.directOnly,
            sendWsJson: (payload) {
              try {
                final bytes = encodeSignaling(payload);
                if (bytes != null) channel.sink.add(bytes);
              } catch (_) {}
            },
          );
          _p2pRtc = rtcClient;
          // pc Failed/Closed（非本端主动关闭）时通知 controller 清理并调度重连：
          // 此前 rtc 内部直接 close 不上报，链路死亡后上层无感知（假在线直到请求超时）
          rtcClient.onConnectionLost = () {
            if (!isCurrentConnectToken()) return;
            if (!identical(_p2pRtc, rtcClient)) return;
            unawaited(
              _handleP2pConnectionLost(
                connectToken,
                Exception('p2p_rtc_connection_lost'),
              ),
            );
          };
          print('🟡 [P2pConnect] 启动 RTC 数据通道...');
          await rtcClient
              .start(
                channels: const <P2pRtcChannel>[
                  P2pRtcChannel.api,
                  P2pRtcChannel.file,
                  // 与独立 upload/download link 复用同一 PeerConnection，避免二次 ICE/信令在中继下超时
                  P2pRtcChannel.upload,
                  P2pRtcChannel.download,
                  // 让视频播放优先复用主连接，避免额外创建 video link 会话
                  P2pRtcChannel.video,
                ],
              )
              .timeout(const Duration(seconds: 10));
        }
        if (!isCurrentConnectToken()) {
          // disconnect 已作废建连意图：不置 ready，交由外层 catch 清理本次资源
          throw Exception('p2p_connect_cancelled');
        }
        // print('🟢 [P2pConnect] RTC 数据通道启动成功');
      } catch (e) {
        print('🔴 [P2pConnect] RTC 初始化失败: $e');
        // auto 偏好打洞失败：立即回退中继(relayOnly)重连一次，
        // 让用户尽快进入服务器；后续连接（含下次登录）仍默认 auto 优先直连
        if (allowRelayFallback &&
            isCurrentConnectToken() &&
            _p2pIcePreference == P2pIcePreference.auto) {
          print('🟠 [P2pConnect] 直连打洞失败，回退中继(relayOnly)重连...');
          relayFallbackStarted = true;
          try {
            await _cleanupP2p(
              disableReconnect: false,
              expectedConnectToken: connectToken,
            );
          } catch (_) {}
          _p2pIcePreference = P2pIcePreference.relayOnly;
          _p2pTransportKind = P2pTransportKind.relay;
          _bumpConnectChannelRevision();
          return await _connectP2pByPairCodeAttempt(
            code,
            resetReconnectAttempts: resetReconnectAttempts,
            allowRelayFallback: false,
          );
        }
        unawaited(
          _cleanupP2p(
            disableReconnect: false,
            expectedConnectToken: connectToken,
          ),
        );
        _scheduleP2pReconnect();
        throw Exception('p2p_rtc_init_failed_$e');
      }

      print('🟢 [P2pConnect] P2P 连接成功! 设置 isP2pReady=true');
      _setP2pReady(true);
      _emitConnectionState('connected');
      _p2pReconnectAttempts = 0;
      _p2pNextConnectAllowedAtMs = 0;
      _p2pActiveIcePreference = _p2pIcePreference;
      _p2pLastConnectError = null;

      unawaited(
        Future.delayed(const Duration(milliseconds: 800), () async {
          if (_p2pRtc != null) {
            try {
              final stats = await _p2pRtc!.getTransportStats();
              final type = stats['type'] ?? '';
              if (type == 'relay') {
                _p2pTransportKind = P2pTransportKind.relay;
                _bumpConnectChannelRevision();
                // 中继确认后主动调度直连升级探测：NetMonitor 等触发点可能在
                // 统计确认前检查（kind 尚为 unknown）而漏触发，导致长期滞留中继
                scheduleP2pDirectUpgrade();
              } else if (type == 'host' || type == 'srflx' || type == 'prflx') {
                _p2pTransportKind = P2pTransportKind.direct;
                _bumpConnectChannelRevision();
              }
            } catch (_) {}
          }
        }),
      );

      try {
        CacheManager().setString(CacheKeys.p2pLastPairCode, code);
      } catch (_) {}
    } catch (e) {
      if (!isCurrentConnectToken()) {
        // 中继回退递归抛出的失败：递归内部已完成清理与重连调度，静默退出
        if (relayFallbackStarted) return;
        // 建连意图已被 disconnect 作废：清理本次尝试新建的 WS/RTC 资源后
        // 静默退出，避免形成用户已断开的僵尸连接（假在线）
        print('🔴 [P2pConnect] 建连意图已作废，清理本次尝试资源并退出: $e');
        try {
          await _cleanupP2p(disableReconnect: true);
        } catch (_) {}
        return;
      }
      print('🔴 [P2pConnect] 连接失败: $e');
      _p2pLastConnectError = e;
      if (resetReconnectAttempts) {
        _emitConnectionState('failed');
      }
      try {
        await _cleanupP2p(
          disableReconnect: false,
          expectedConnectToken: connectToken,
        );
      } catch (_) {}
      if (previousBaseUrl.trim().isNotEmpty &&
          previousBaseUrl.trim() != ApiController.p2pBaseUrl) {
        setBaseUrl(previousBaseUrl);
      }
      if (previousBaseUrl.trim() == ApiController.p2pBaseUrl) {
        _scheduleP2pReconnect();
      }
      rethrow;
    }
  }

  /// 深比较两份 iceServers（预热用的 HTTP 响应 vs session:ready 下发）。
  /// 同源（同一会话 ticket）时必相等；不一致说明 TURN 凭据轮换等，需废弃预热
  bool _iceServersDeepEqual(List<dynamic> a, List<dynamic>? b) {
    if (b == null) return false;
    if (identical(a, b)) return true;
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }

  List<dynamic> _applyIcePreference(
    List<dynamic> iceServers,
    P2pIcePreference pref,
  ) {
    if (pref == P2pIcePreference.auto) return iceServers;

    final out = <dynamic>[];
    for (final s in iceServers) {
      if (s is! Map) continue;
      final urls = s['urls'];
      final urlList = <String>[];
      if (urls is String) {
        final u = urls.trim();
        if (u.isNotEmpty) urlList.add(u);
      } else if (urls is List) {
        for (final e in urls) {
          final u = (e ?? '').toString().trim();
          if (u.isNotEmpty) urlList.add(u);
        }
      }

      final hasTurn = urlList.any(_isTurnUrl);
      if (pref == P2pIcePreference.directOnly) {
        if (hasTurn) {
          final nextUrls = urlList.where((u) => !_isTurnUrl(u)).toList();
          if (nextUrls.isEmpty) continue;
          final next = Map<String, dynamic>.from(s);
          next['urls'] = nextUrls.length == 1 ? nextUrls.first : nextUrls;
          out.add(next);
        } else {
          out.add(s);
        }
      } else if (pref == P2pIcePreference.relayOnly) {
        if (!hasTurn) continue;
        final nextUrls = urlList.where(_isTurnUrl).toList();
        if (nextUrls.isEmpty) continue;
        final next = Map<String, dynamic>.from(s);
        next['urls'] = nextUrls.length == 1 ? nextUrls.first : nextUrls;
        out.add(next);
      }
    }

    if (pref == P2pIcePreference.relayOnly) {
      final hasAnyTurn = out.any((s) {
        if (s is! Map) return false;
        final urls = s['urls'];
        if (urls is String) return _isTurnUrl(urls);
        if (urls is List) {
          return urls.any((e) => _isTurnUrl((e ?? '').toString()));
        }
        return false;
      });
      if (!hasAnyTurn) {
        throw Exception('p2p_relay_not_available');
      }
    }

    return out.isEmpty ? iceServers : out;
  }

  bool _isTurnUrl(String url) {
    final s = url.trim().toLowerCase();
    return s.startsWith('turn:') || s.startsWith('turns:');
  }

  String _extractTurnServerAddress(List<dynamic> iceServers) {
    for (final s in iceServers) {
      if (s is! Map) continue;
      final urls = s['urls'];
      final urlList = <String>[];
      if (urls is String) {
        final u = urls.trim();
        if (u.isNotEmpty) urlList.add(u);
      } else if (urls is List) {
        for (final e in urls) {
          final u = (e ?? '').toString().trim();
          if (u.isNotEmpty) urlList.add(u);
        }
      }
      for (final u in urlList) {
        if (!_isTurnUrl(u)) continue;
        final noScheme = u.replaceFirst(
          RegExp(r'^turns?:', caseSensitive: false),
          '',
        );
        final atSplit = noScheme.split('@');
        final hostPart = (atSplit.length == 2 ? atSplit[1] : atSplit[0]).trim();
        final qIndex = hostPart.indexOf('?');
        return (qIndex >= 0 ? hostPart.substring(0, qIndex) : hostPart).trim();
      }
    }
    return '';
  }

  bool _shouldSkipP2pReconnectForPath(String path) {
    final normalized = path.trim();
    return normalized == '/api/hw/metrics';
  }

  Future<P2pRtcClient> _p2pRtcForChannel(
    P2pRtcChannel channel, {
    Duration timeout = const Duration(seconds: 20),
    bool ensureConnected = true,
  }) async {
    // 单主连接策略：所有请求统一复用主 RTC，不再创建 upload/download/video 独立 link。
    if (ensureConnected) {
      final ok = await ensureP2pConnected(timeout: timeout);
      if (!ok) throw Exception('p2p_not_connected');
    }

    final rtc = _p2pRtc;
    if (rtc == null) throw Exception('p2p_not_connected');

    if (channel != P2pRtcChannel.api) {
      // 建连成功只 gate api 通道：其余通道（file/upload/download/video）与
      // api 同一 PC 协商、陆续 open，可能尚在握手。先等待而非立即失败，
      // 避免把「握手未完成」误判为断连触发全局 forceReconnect
      //（waitChannelOpen 首轮即检查，已 open 时零延迟返回）
      if (!await rtc.waitChannelOpen(channel)) {
        throw Exception('p2p_dc_not_open');
      }
    } else if (!rtc.isApiChannelOpen) {
      // api 通道在建连成功时已保证 open：此刻不 open 即真断连，走重连
      throw Exception('p2p_dc_not_open');
    }
    return rtc;
  }

  Future<http.StreamedResponse> sendP2pRequest(
    http.BaseRequest request, {
    Duration? timeout,
    Future<void>? cancelFuture,
  }) async {
    final uri = request.url;
    final resolved = P2pChannelUtil.resolve(uri: uri);
    final path = resolved.path;
    final skipReconnect = _shouldSkipP2pReconnectForPath(path);
    final bodyBytes = request is http.Request
        ? request.bodyBytes
        : await http.ByteStream(request.finalize()).toBytes();

    Future<P2pApiResponse> sendOnce() async {
      final chan = resolved.channel;
      final rtc = await _p2pRtcForChannel(
        chan,
        timeout: const Duration(seconds: 20),
        ensureConnected: !skipReconnect,
      );
      return rtc.sendRequest(
        channel: chan,
        method: request.method,
        path: path,
        headers: request.headers,
        bodyBytes: bodyBytes,
        timeout: timeout ?? const Duration(minutes: 5),
        cancelFuture: cancelFuture,
      );
    }

    if (!skipReconnect && !isP2pReady) {
      await ensureP2pConnected(timeout: const Duration(seconds: 15));
    }

    P2pApiResponse res;
    try {
      res = await sendOnce();
    } catch (e) {
      if (!skipReconnect &&
          _isP2pReconnectableError(e) &&
          !_isMainP2pConnectionAlive()) {
        if (_p2pReconnectInFlight != null) {
          rethrow;
        }
        final ok = await _forceReconnectP2p(
          timeout: const Duration(seconds: 15),
        );
        if (ok) {
          res = await sendOnce();
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([res.bodyBytes]),
      res.status,
      contentLength: res.bodyBytes.length,
      headers: res.headers,
      request: request,
    );
  }

  Future<http.StreamedResponse> sendP2pRequestOnChannel(
    http.BaseRequest request, {
    Duration? timeout,
    required P2pRtcChannel channel,
    Future<void>? cancelFuture,
  }) async {
    final uri = request.url;
    final resolved = P2pChannelUtil.resolve(uri: uri, fallbackChannel: channel);
    final path = resolved.path;
    final skipReconnect = _shouldSkipP2pReconnectForPath(path);
    final effectiveChannel = resolved.channel;
    final bodyBytes = request is http.Request
        ? request.bodyBytes
        : await http.ByteStream(request.finalize()).toBytes();

    Future<P2pApiResponse> sendOnce() async {
      final rtc = await _p2pRtcForChannel(
        effectiveChannel,
        timeout: const Duration(seconds: 20),
        ensureConnected: !skipReconnect,
      );
      return rtc.sendRequest(
        channel: effectiveChannel,
        method: request.method,
        path: path,
        headers: request.headers,
        bodyBytes: bodyBytes,
        timeout: timeout ?? const Duration(minutes: 5),
        cancelFuture: cancelFuture,
      );
    }

    if (!skipReconnect && !isP2pReady) {
      await ensureP2pConnected(timeout: const Duration(seconds: 15));
    }

    P2pApiResponse res;
    try {
      res = await sendOnce();
    } catch (e) {
      if (!skipReconnect &&
          _isP2pReconnectableError(e) &&
          !_isMainP2pConnectionAlive()) {
        if (_p2pReconnectInFlight != null) {
          rethrow;
        }
        final ok = await _forceReconnectP2p(
          timeout: const Duration(seconds: 15),
        );
        if (ok) {
          res = await sendOnce();
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([res.bodyBytes]),
      res.status,
      contentLength: res.bodyBytes.length,
      headers: res.headers,
      request: request,
    );
  }

  Future<P2pStreamedResponse> sendP2pStreamRequest(
    http.BaseRequest request, {
    Duration? timeout,
    P2pRtcChannel channel = P2pRtcChannel.video,
  }) async {
    final uri = request.url;
    final resolved = P2pChannelUtil.resolve(uri: uri, fallbackChannel: channel);
    final effectiveChannel = resolved.channel;
    final path = resolved.path;
    final skipReconnect = _shouldSkipP2pReconnectForPath(path);
    final bodyBytes = request is http.Request
        ? request.bodyBytes
        : await http.ByteStream(request.finalize()).toBytes();

    Future<P2pApiStreamResponse> sendOnce() async {
      final rtc = await _p2pRtcForChannel(
        effectiveChannel,
        timeout: const Duration(seconds: 20),
        ensureConnected: !skipReconnect,
      );
      return rtc.sendRequestStream(
        channel: effectiveChannel,
        method: request.method,
        path: path,
        headers: request.headers,
        bodyBytes: bodyBytes,
        timeout: timeout ?? const Duration(minutes: 5),
      );
    }

    if (!skipReconnect && !isP2pReady) {
      await ensureP2pConnected(timeout: const Duration(seconds: 15));
    }

    try {
      final res = await sendOnce();
      return P2pStreamedResponse(
        status: res.status,
        headers: res.headers,
        stream: res.stream,
        cancel: res.cancel,
      );
    } catch (e) {
      if (!skipReconnect &&
          _isP2pReconnectableError(e) &&
          !_isMainP2pConnectionAlive()) {
        if (_p2pReconnectInFlight != null) {
          rethrow;
        }
        final ok = await _forceReconnectP2p(
          timeout: const Duration(seconds: 15),
        );
        if (ok) {
          final res = await sendOnce();
          return P2pStreamedResponse(
            status: res.status,
            headers: res.headers,
            stream: res.stream,
            cancel: res.cancel,
          );
        }
      }
      final streamed = await sendP2pRequest(request, timeout: timeout);
      return P2pStreamedResponse(
        status: streamed.statusCode,
        headers: streamed.headers,
        stream: streamed.stream.map((e) => Uint8List.fromList(e)),
        cancel: () {},
      );
    }
  }

  WebSocketChannel connectP2pWebSocketChannel(Uri uri) {
    final rtc = _p2pRtc;
    if (rtc == null) {
      throw Exception('p2p_not_connected');
    }
    final resolved = P2pChannelUtil.resolve(uri: uri);
    final path = resolved.path;
    final chan = resolved.channel;
    return rtc.openWebSocketChannel(channel: chan, path: path);
  }

  WebSocketChannel connectP2pWebSocketChannelLazy(Uri uri) {
    return _DeferredWebSocketChannel(() async {
      final ok = await ensureP2pConnected();
      if (!ok) {
        throw Exception('p2p_not_connected');
      }
      return connectP2pWebSocketChannel(uri);
    });
  }

  Future<Map<String, dynamic>> _createP2pSession(String pairCode) async {
    final uri = Uri.parse(
      '${ApiController.signalApiBaseUrl}'
      '/api/p2p/pair/session/create',
    );
    print('🟢 [P2pSession] 创建会话请求: $uri');
    print('🟢 [P2pSession] 配对码: "$pairCode"');
    final http.Client client;
    if (kIsWeb) {
      client = http.Client();
    } else {
      client = IOClient(
        HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true,
      );
    }
    try {
      final token = (CacheManager().getString(CacheKeys.nascabOsJwt) ?? '')
          .trim();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        print('🟢 [P2pSession] 携带 JWT Token, 长度: ${token.length}');
      } else {
        print('🟢 [P2pSession] 未携带 JWT Token');
      }
      final body = <String, dynamic>{'pairCode': pairCode};
      print('🟢 [P2pSession] 请求体: $body');
      final res = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      print('🟢 [P2pSession] 响应状态码: ${res.statusCode}');
      print('🟢 [P2pSession] 响应体: ${res.body}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('pair_session_http_${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('pair_session_invalid_response');
      }
      final dataRaw = decoded['data'];
      if (dataRaw is Map<String, dynamic>) {
        print('🟢 [P2pSession] 返回 data: $dataRaw');
        return dataRaw;
      }
      if (dataRaw is Map) {
        final result = Map<String, dynamic>.from(dataRaw);
        print('🟢 [P2pSession] 返回 data (converted): $result');
        return result;
      }
      print('🟢 [P2pSession] 返回 decoded: $decoded');
      return decoded;
    } catch (e) {
      print('🔴 [P2pSession] 创建会话失败: $e');
      rethrow;
    } finally {
      client.close();
    }
  }
}

class P2pStreamedResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<Uint8List> stream;
  final void Function() cancel;

  const P2pStreamedResponse({
    required this.status,
    required this.headers,
    required this.stream,
    required this.cancel,
  });
}

class _DeferredWebSocketChannel
    with StreamChannelMixin
    implements WebSocketChannel {
  _DeferredWebSocketChannel(this._open)
    : _incoming = StreamController<dynamic>(sync: true),
      _sinkController = StreamController<dynamic>(sync: true),
      _ready = Completer<void>() {
    sink = _DeferredWebSocketSink(_sinkController.sink, onClose: _closeLocal);
    _sinkSub = _sinkController.stream.listen(_handleOutgoingAdd);
    _start();
  }

  final Future<WebSocketChannel> Function() _open;
  final StreamController<dynamic> _incoming;
  final StreamController<dynamic> _sinkController;
  final Completer<void> _ready;
  StreamSubscription<dynamic>? _sinkSub;
  WebSocketChannel? _delegate;
  StreamSubscription? _delegateSub;
  bool _closed = false;

  final List<dynamic> _pendingOutgoing = <dynamic>[];

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream get stream => _incoming.stream;

  @override
  late final WebSocketSink sink;

  void _start() async {
    try {
      final ch = await _open();
      if (_closed) {
        try {
          ch.sink.close();
        } catch (_) {}
        return;
      }
      _delegate = ch;
      _delegateSub = ch.stream.listen(
        (event) {
          if (_closed) return;
          _incoming.add(event);
        },
        onError: (e) {
          if (_closed) return;
          _incoming.addError(e);
        },
        onDone: () {
          if (_closed) return;
          closeCode = ch.closeCode;
          closeReason = ch.closeReason;
          _incoming.close();
        },
        cancelOnError: false,
      );
      if (!_ready.isCompleted) _ready.complete();
      for (final m in _pendingOutgoing) {
        try {
          ch.sink.add(m);
        } catch (_) {}
      }
      _pendingOutgoing.clear();
    } catch (e) {
      if (!_ready.isCompleted) _ready.completeError(e);
      if (!_closed) {
        _incoming.addError(e);
        _incoming.close();
      }
    }
  }

  void _handleOutgoingAdd(dynamic data) {
    if (_closed) return;
    final ch = _delegate;
    if (ch == null) {
      _pendingOutgoing.add(data);
      return;
    }
    try {
      ch.sink.add(data);
    } catch (e) {
      _incoming.addError(e);
    }
  }

  void _closeLocal([int? code, String? reason]) {
    if (_closed) return;
    _closed = true;
    closeCode = code;
    closeReason = reason;
    try {
      _sinkSub?.cancel();
    } catch (_) {}
    _sinkSub = null;
    try {
      _delegateSub?.cancel();
    } catch (_) {}
    _delegateSub = null;
    try {
      _delegate?.sink.close(code, reason);
    } catch (_) {}
    _delegate = null;
    try {
      _incoming.close();
    } catch (_) {}
  }
}

class _DeferredWebSocketSink implements WebSocketSink {
  _DeferredWebSocketSink(this._delegate, {required this.onClose});

  final StreamSink<dynamic> _delegate;
  final void Function([int? code, String? reason]) onClose;

  @override
  void add(dynamic data) => _delegate.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _delegate.addError(error, stackTrace);

  @override
  Future addStream(Stream stream) => _delegate.addStream(stream);

  @override
  Future close([int? closeCode, String? closeReason]) async {
    onClose(closeCode, closeReason);
    await _delegate.close();
  }

  @override
  Future get done => _delegate.done;
}
