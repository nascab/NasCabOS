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
        s.contains('p2p_dc_not_open');
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
    if (Platform.isWindows) return false;
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

  void _scheduleP2pReconnect() {
    if (!_p2pAllowReconnect) return;
    final code = _p2pLastPairCode.trim();
    if (code.isEmpty) return;
    if (_p2pReconnectTimer != null) return;

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
        s.contains('pair_session_http_410') ||
        s.contains('pair_session_http_403')) {
      return 15;
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
    } else if (!kDebugMode) {
      _p2pIcePreference = P2pIcePreference.auto;
      _p2pTransportKind = P2pTransportKind.unknown;
      _bumpConnectChannelRevision();
    }
    if (resetReconnectAttempts) {
      _p2pReconnectAttempts = 0;
      try {
        _p2pReconnectTimer?.cancel();
      } catch (_) {}
      _p2pReconnectTimer = null;
    }
    final task = _p2pConnectQueue.then(
      (_) => _connectP2pByPairCodeLocked(
        code,
        resetReconnectAttempts: resetReconnectAttempts,
      ),
    );
    _p2pConnectQueue = task.catchError((_) {});
    return task;
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

    try {
      print('🟡 [P2pConnect] 清理旧连接...');
      await _cleanupP2p(
        disableReconnect: false,
        expectedConnectToken: connectToken,
      );
      if (kIsWeb) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      print('🟡 [P2pConnect] 调用 _createP2pSession...');
      final session = await _createP2pSession(code);

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
            _p2pLastConnectError = Exception('p2p_ws_error_$code');
            if (!ready.isCompleted) {
              ready.completeError(Exception('p2p_ws_error_$code'));
            }
            unawaited(
              _cleanupP2p(
                disableReconnect: false,
                expectedConnectToken: connectToken,
              ),
            );
            _scheduleP2pReconnect();
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
              unawaited(
                _cleanupP2p(
                  disableReconnect: false,
                  expectedConnectToken: connectToken,
                ),
              );
              _scheduleP2pReconnect();
              return;
            }
            print('🟢 [P2pConnect] ready.complete() 被调用');
            if (!ready.isCompleted) ready.complete();
            return;
          }
          if (type == 'session:closed') {
            print('🔴 [P2pConnect] session:closed 收到');
            unawaited(
              _cleanupP2p(
                disableReconnect: false,
                expectedConnectToken: connectToken,
              ),
            );
            _scheduleP2pReconnect();
            return;
          }
        },
        onError: (e) {
          if (!isCurrentConnectToken()) return;
          print('🔴 [P2pConnect] WebSocket onError: $e');
          _p2pLastConnectError = Exception('p2p_ws_error');
          if (!ready.isCompleted) {
            ready.completeError(Exception('p2p_ws_error'));
          }
          unawaited(
            _cleanupP2p(
              disableReconnect: false,
              expectedConnectToken: connectToken,
            ),
          );
          _scheduleP2pReconnect();
        },
        onDone: () {
          if (!isCurrentConnectToken()) return;
          print('🔴 [P2pConnect] WebSocket onDone (closed)');
          _p2pLastConnectError = Exception('p2p_ws_closed');
          if (!ready.isCompleted) {
            ready.completeError(Exception('p2p_ws_closed'));
          }
          unawaited(
            _cleanupP2p(
              disableReconnect: false,
              expectedConnectToken: connectToken,
            ),
          );
          _scheduleP2pReconnect();
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
        _p2pRelayAddress = _extractTurnServerAddress(_p2pIceServers);
        print(
          '🟡 [P2pConnect] 初始化 P2pRtcClient, sessionId=$sid, relayAddress=$_p2pRelayAddress',
        );
        _bumpConnectChannelRevision();
        _p2pRtc = P2pRtcClient(
          sessionId: sid,
          iceServers: _p2pIceServers,
          iceTransportPolicy: _p2pIcePreference == P2pIcePreference.relayOnly
              ? 'relay'
              : null,
          sendWsJson: (payload) {
            try {
              final bytes = encodeSignaling(payload);
              if (bytes != null) channel.sink.add(bytes);
            } catch (_) {}
          },
        );
        print('🟡 [P2pConnect] 启动 RTC 数据通道...');
        await _p2pRtc!
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
            .timeout(const Duration(seconds: 20));
        // print('🟢 [P2pConnect] RTC 数据通道启动成功');
      } catch (e) {
        print('🔴 [P2pConnect] RTC 初始化失败: $e');
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
      if (!isCurrentConnectToken()) return;
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

    if (channel == P2pRtcChannel.upload && !rtc.isUploadChannelOpen) {
      throw Exception('p2p_dc_not_open');
    }
    if (channel == P2pRtcChannel.download && !rtc.isDownloadChannelOpen) {
      throw Exception('p2p_dc_not_open');
    }
    if (channel == P2pRtcChannel.video && !rtc.isVideoChannelOpen) {
      throw Exception('p2p_dc_not_open');
    }
    if (channel == P2pRtcChannel.api && !rtc.isApiChannelOpen) {
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
