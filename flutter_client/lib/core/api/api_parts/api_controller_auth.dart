part of '../api_controller.dart';

/// 从 auth_serverId 变形生成 AES 密钥与 IV，用于 token 加解密
(List<int> keyBytes, List<int> ivBytes) _deriveKeyFromServerId(
  String serverId,
) {
  const keySalt = 'nascab_auth_key_v1_';
  const ivSalt = 'nascab_auth_iv_v1_';
  final keyHash = sha256.convert(utf8.encode(keySalt + serverId)).bytes;
  final ivHash = sha256.convert(utf8.encode(ivSalt + serverId)).bytes;
  return (keyHash, ivHash.sublist(0, 16));
}

String? _encryptToken(String plaintext, String serverId) {
  if (serverId.isEmpty || plaintext.isEmpty) {
    return plaintext.isEmpty ? null : plaintext;
  }
  try {
    final (keyBytes, ivBytes) = _deriveKeyFromServerId(serverId);
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.encrypt(plaintext, iv: iv).base64;
  } catch (_) {
    return null;
  }
}

String? _decryptToken(String? cipherBase64, String serverId) {
  if (serverId.isEmpty || cipherBase64 == null || cipherBase64.isEmpty) {
    return cipherBase64;
  }
  try {
    final (keyBytes, ivBytes) = _deriveKeyFromServerId(serverId);
    final key = encrypt.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt64(cipherBase64, iv: iv);
  } catch (_) {
    return null;
  }
}

extension ApiControllerAuth on ApiController {
  /// 设置当前客户端与服务器是否在同一台机器上运行
  void setSameMachine(bool value) {
    if (_state.isSameMachine == value) return;
    _state = _state.copyWith(isSameMachine: value);
    update();
  }

  /// 当前客户端与已登录的服务器是否在同一台机器上
  bool get isSameMachine => _state.isSameMachine;

  void setAuthInfo({
    required String serverId,
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    bool shellSupported = false,
    String? httpsPort,
    String? serverPlatform,
    String? serverVersion,
    String? serverHostname,
    String? customHostname,
    /// 仅刷新 access/refresh token 时为 false，避免清空图片缓存与重建连接通道导致壁纸闪烁。
    bool refreshSessionChannel = true,
  }) {
    print('设置认证信息: $shellSupported');
    final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresIn * 1000);
    final chRaw = customHostname?.trim();
    final ch = (chRaw == null || chRaw.isEmpty) ? null : chRaw;

    _state = ApiState(
      serverId: serverId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      baseUrl: _state.baseUrl,
      isAuthenticated: true,
      expiresIn: expiryTime,
      shellSupported: shellSupported,
      httpsPort: httpsPort,
      serverPlatform: serverPlatform,
      serverVersion: serverVersion,
      serverHostname: serverHostname,
      customHostname: ch,
    );

    if (refreshSessionChannel) {
      CustomExtendedImage.invalidateSessionCaches();
      _bumpConnectChannelRevision();
    }
    update();
    _saveTokensToStorage();
    _startTokenRefreshTimer();
    unawaited(startGlobalNetworkMonitor());
    AppWindowTitle.applyForSession(ch);
    if (Get.isRegistered<PhotoBackupController>()) {
      final photoBackup = Get.find<PhotoBackupController>();
      photoBackup.onSessionMaybeChanged();
      // 登录/刷新 token 已证明当前连接可用，再触发「APP 打开时自动开启备份」
      photoBackup.onConnectionConfirmed();
    }
  }

  /// 设置会话中的自定义主机名（如设置页保存后），并同步本地缓存
  void setSessionCustomHostname(String? customHostname) {
    final chRaw = customHostname?.trim();
    final ch = (chRaw == null || chRaw.isEmpty) ? null : chRaw;
    _state = ApiState(
      serverId: _state.serverId,
      accessToken: _state.accessToken,
      refreshToken: _state.refreshToken,
      baseUrl: _state.baseUrl,
      isAuthenticated: _state.isAuthenticated,
      expiresIn: _state.expiresIn,
      shellSupported: _state.shellSupported,
      httpsPort: _state.httpsPort,
      serverPlatform: _state.serverPlatform,
      serverVersion: _state.serverVersion,
      serverHostname: _state.serverHostname,
      customHostname: ch,
    );
    update();
    _saveTokensToStorage();
    AppWindowTitle.applyForSession(ch);
  }

  String? get customHostname => _state.customHostname;

  void clearAuthInfo() {
    CustomExtendedImage.invalidateSessionCaches();
    final wasP2pMode = isP2pMode;
    _state = ApiState(
      serverId: _state.serverId,
      baseUrl: _state.baseUrl,
      isAuthenticated: false,
      shellSupported: _state.shellSupported,
    );

    _bumpConnectChannelRevision();
    update();
    AppWindowTitle.applyDefault();
    _clearStoredTokens();
    _refreshTimer?.cancel();
    stopGlobalNetworkMonitor();
    disconnectP2p().catchError((_) {});
    if (wasP2pMode) {
      setBaseUrl(ApiController._getDefaultBaseUrl());
    }
    if (Get.isRegistered<PhotoBackupController>()) {
      Get.find<PhotoBackupController>().onSessionMaybeChanged();
    }
  }

  String? get accessToken => _state.accessToken;

  String? get refreshToken => _state.refreshToken;

  String get baseUrl => _state.baseUrl;

  /// 服务器 OS 平台，如 darwin/win32/linux
  String? get serverPlatform => _state.serverPlatform;

  /// 服务器当前版本（登录接口返回，已持久化）
  String? get serverVersion => _state.serverVersion;

  int? get serverMajorVersion =>
      ServerVersionUtil.parseMajorVersion(_state.serverVersion);

  bool isServerVersionAtLeast(
    int majorVersion, {
    bool unknownAsSupported = true,
  }) {
    return ServerVersionUtil.isAtLeast(
      _state.serverVersion,
      majorVersion,
      unknownAsSupported: unknownAsSupported,
    );
  }

  /// 服务器 hostname（登录/设权时传入，用于同机备份路径校验等）
  String? get serverHostname => _state.serverHostname;

  bool get isAuthenticated => _state.isAuthenticated;

  bool get isTokenExpiringSoon {
    final expiresIn = _state.expiresIn;
    if (expiresIn == null) return false;
    final now = DateTime.now();
    final timeUntilExpiry = expiresIn.difference(now);
    final seconds = timeUntilExpiry.inSeconds;
    final minutes = seconds / 60.0;
    print('距离token过期时间(秒): $seconds秒, 约${minutes.toStringAsFixed(1)}分钟');
    return seconds <= 300;
  }

  Future<bool> refreshAuthToken() async {
    final existing = _refreshAuthTokenInFlight;
    if (existing != null) {
      return await existing;
    }
    final task = _performRefreshAuthToken();
    _refreshAuthTokenInFlight = task;
    try {
      return await task;
    } finally {
      if (identical(_refreshAuthTokenInFlight, task)) {
        _refreshAuthTokenInFlight = null;
      }
    }
  }

  Future<bool> _performRefreshAuthToken() async {
    final currentRefreshToken = _state.refreshToken;
    if (currentRefreshToken == null) return false;
    try {
      final response = await AuthApiService.instance.refreshTokenApi(
        currentRefreshToken,
      );
      if (!response.success ||
          response.serverId == null ||
          response.accessToken == null ||
          response.refreshToken == null ||
          response.expiresIn == null) {
        return false;
      }
      setAuthInfo(
        serverId: response.serverId!,
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken!,
        expiresIn: response.expiresIn!,
        shellSupported: _state.shellSupported,
        serverPlatform: _state.serverPlatform,
        serverVersion: _state.serverVersion,
        serverHostname: _state.serverHostname,
        customHostname: _state.customHostname,
        refreshSessionChannel: false,
      );
      return true;
    } catch (e) {
      print('刷新jwt失败: $e');
    }
    return false;
  }

  void _startTokenRefreshTimer() {
    _refreshTimer?.cancel();
    if (!_state.isAuthenticated) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (isTokenExpiringSoon) {
        await refreshAuthToken();
      }
    });
  }

  void _loadStoredTokens() {
    try {
      final storedBaseUrl = CacheManager().getString('auth_baseUrl');
      if (storedBaseUrl != null && storedBaseUrl.isNotEmpty) {
        _state = _state.copyWith(baseUrl: storedBaseUrl);
      }
      final storedHttpsPort = CacheManager().getString('auth_httpsPort');
      if (storedHttpsPort != null && storedHttpsPort.isNotEmpty) {
        _state = _state.copyWith(httpsPort: storedHttpsPort);
      }
      final serverId = CacheManager().getString('auth_serverId') ?? '';
      final rawAccessToken = CacheManager().getString('auth_accessToken');
      final rawRefreshToken = CacheManager().getString('auth_refreshToken');
      final storedAccessToken =
          _decryptToken(rawAccessToken, serverId) ?? rawAccessToken;
      final storedRefreshToken =
          _decryptToken(rawRefreshToken, serverId) ?? rawRefreshToken;
      final expiryTimestamp = CacheManager().getInt('auth_expiresIn');
      final shellSupported =
          CacheManager().getBool('auth_shellSupported') ?? false;
      final serverPlatform = CacheManager().getString('auth_serverPlatform');
      final serverVersion = CacheManager().getString('auth_serverVersion');
      final serverHostname = CacheManager().getString('auth_serverHostname');
      final customHostname = CacheManager().getString('auth_customHostname');

      DateTime? expiry;
      if (expiryTimestamp != null && expiryTimestamp > 0) {
        expiry = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp);
      }

      final isValid = expiry != null && expiry.isAfter(DateTime.now());

      _state = _state.copyWith(
        serverId: serverId,
        accessToken: isValid ? storedAccessToken : null,
        refreshToken: storedRefreshToken,
        isAuthenticated: isValid && storedAccessToken != null,
        expiresIn: expiry,
        shellSupported: shellSupported,
        serverPlatform: serverPlatform,
        serverVersion: serverVersion,
        serverHostname: serverHostname,
        customHostname: customHostname,
      );

      _startTokenRefreshTimer();

      // 冷启动时若已登录，启动全局网络监控
      if (_state.isAuthenticated) {
        unawaited(startGlobalNetworkMonitor());
        AppWindowTitle.applyForSession(_state.customHostname);
      }

      if (!isValid &&
          (storedRefreshToken != null && storedRefreshToken.isNotEmpty)) {
        refreshAuthToken();
      }
    } catch (e) {
      print('Failed to load stored tokens: $e');
    }
  }

  void _saveTokensToStorage() {
    try {
      CacheManager().setString('auth_baseUrl', _state.baseUrl);
      if (_state.httpsPort != null && _state.httpsPort!.isNotEmpty) {
        CacheManager().setString('auth_httpsPort', _state.httpsPort!);
      }
      CacheManager().setString('auth_serverId', _state.serverId);
      final accessTokenRaw = _state.accessToken ?? '';
      final refreshTokenRaw = _state.refreshToken ?? '';
      final accessToStore =
          _encryptToken(accessTokenRaw, _state.serverId) ?? accessTokenRaw;
      final refreshToStore =
          _encryptToken(refreshTokenRaw, _state.serverId) ?? refreshTokenRaw;
      CacheManager().setString('auth_accessToken', accessToStore);
      CacheManager().setString('auth_refreshToken', refreshToStore);
      CacheManager().setInt(
        'auth_expiresIn',
        _state.expiresIn?.millisecondsSinceEpoch ?? 0,
      );
      CacheManager().setBool('auth_shellSupported', _state.shellSupported);
      if (_state.serverPlatform != null && _state.serverPlatform!.isNotEmpty) {
        CacheManager().setString('auth_serverPlatform', _state.serverPlatform!);
      }
      if (_state.serverVersion != null && _state.serverVersion!.isNotEmpty) {
        CacheManager().setString('auth_serverVersion', _state.serverVersion!);
      }
      if (_state.serverHostname != null && _state.serverHostname!.isNotEmpty) {
        CacheManager().setString('auth_serverHostname', _state.serverHostname!);
      }
      if (_state.customHostname != null && _state.customHostname!.isNotEmpty) {
        CacheManager().setString('auth_customHostname', _state.customHostname!);
      } else {
        CacheManager().remove('auth_customHostname');
      }
    } catch (e) {
      print('Failed to save tokens: $e');
    }
  }

  void _clearStoredTokens() {
    try {
      CacheManager().remove('auth_accessToken');
      CacheManager().remove('auth_refreshToken');
      CacheManager().remove('auth_expiresIn');
      CacheManager().remove('auth_serverId');
      CacheManager().remove('auth_baseUrl');
      CacheManager().remove('auth_httpsPort');
      CacheManager().remove('auth_shellSupported');
      CacheManager().remove('auth_serverPlatform');
      CacheManager().remove('auth_serverVersion');
      CacheManager().remove('auth_serverHostname');
      CacheManager().remove('auth_customHostname');
    } catch (e) {
      print('Failed to clear tokens: $e');
    }
  }
}
