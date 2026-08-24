class ApiState {
  final String? accessToken;
  final String? refreshToken;
  final String baseUrl;
  final String serverId;

  final bool isAuthenticated;
  final DateTime? expiresIn;
  final bool shellSupported;

  /// 登录接口返回的 HTTPS 端口，非 Web 端终端 WebSocket 使用 wss + 此端口
  final String? httpsPort;

  /// 服务器 OS 平台，如 darwin/win32/linux
  final String? serverPlatform;

  /// 服务器当前版本（登录接口返回）
  final String? serverVersion;

  /// 服务器 hostname（登录/设权时传入，用于同机备份路径校验等）
  final String? serverHostname;

  /// 服务端自定义主机名（登录返回，可写入本地服务器条目）
  final String? customHostname;

  /// 客户端与已登录的服务器是否运行在同一台机器上
  final bool isSameMachine;

  const ApiState({
    required this.serverId,
    this.accessToken,
    this.refreshToken,
    required this.baseUrl,
    this.isAuthenticated = false,
    this.expiresIn,
    this.shellSupported = false,
    this.httpsPort,
    this.serverPlatform,
    this.serverVersion,
    this.serverHostname,
    this.customHostname,
    this.isSameMachine = false,
  });

  ApiState copyWith({
    String? serverId,
    String? accessToken,
    String? refreshToken,
    String? baseUrl,
    bool? isAuthenticated,
    DateTime? expiresIn,
    bool? shellSupported,
    String? httpsPort,
    String? serverPlatform,
    String? serverVersion,
    String? serverHostname,
    String? customHostname,
    bool? isSameMachine,
  }) {
    return ApiState(
      serverId: serverId ?? this.serverId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      baseUrl: baseUrl ?? this.baseUrl,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      expiresIn: expiresIn ?? this.expiresIn,
      shellSupported: shellSupported ?? this.shellSupported,
      httpsPort: httpsPort ?? this.httpsPort,
      serverPlatform: serverPlatform ?? this.serverPlatform,
      serverVersion: serverVersion ?? this.serverVersion,
      serverHostname: serverHostname ?? this.serverHostname,
      customHostname: customHostname ?? this.customHostname,
      isSameMachine: isSameMachine ?? this.isSameMachine,
    );
  }

  @override
  String toString() {
    return 'ApiState(accessToken: $accessToken, refreshToken: $refreshToken, baseUrl: $baseUrl, isAuthenticated: $isAuthenticated, expiresIn: $expiresIn, shellSupported: $shellSupported, httpsPort: $httpsPort, serverPlatform: $serverPlatform, serverVersion: $serverVersion)';
  }
}
