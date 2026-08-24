/// 登录响应数据模型
class LoginResponse {
  final bool success;
  final String? message;
  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? user;
  final bool? twoFactorRequired;
  final String? tempToken;
  final String? platform;
  final String? hostname;
  /// 服务端配置的自定义主机名（可为 null）
  final String? customHostname;
  final String? serverId;
  final String? httpPort;
  final String? httpsPort;
  final String? lanIpv4;
  final bool? p2pRemoteAccessEnabled;
  final String? pairCode;
  final int? expiresIn;
  final int? code;
  final Map<String, dynamic>? apps;
  final Map<String, dynamic>? wallpaper;
  final bool? shellSupported;

  /// 服务器当前版本（登录接口返回）
  final String? serverVersion;
  LoginResponse({
    this.code,
    required this.success,
    this.message,
    this.accessToken,
    this.refreshToken,
    this.user,
    this.twoFactorRequired,
    this.tempToken,
    this.platform,
    this.hostname,
    this.customHostname,
    this.serverId,
    this.httpPort,
    this.httpsPort,
    this.lanIpv4,
    this.p2pRemoteAccessEnabled,
    this.pairCode,
    this.expiresIn,
    this.apps,
    this.wallpaper,
    this.shellSupported,
    this.serverVersion,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json, int code) {
    // 检查是否是完整的响应格式（包含success字段）
    // 这可能是仅data字段的内容

    return LoginResponse(
      code: code,
      success: true, // 当从dataParser调用时，假设success为true
      message: null,
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      user: json['user'],
      twoFactorRequired: json['twoFactorRequired'] == true,
      tempToken: json['tempToken'],
      platform: json['platform'],
      hostname: json['hostname'],
      customHostname: () {
        final raw = json['customHostname']?.toString().trim();
        if (raw == null || raw.isEmpty) return null;
        return raw;
      }(),
      serverId: json['serverId'],
      httpPort: json['httpPort'],
      httpsPort: json['httpsPort'],
      lanIpv4: json['lanIpv4']?.toString(),
      p2pRemoteAccessEnabled: json['p2pRemoteAccessEnabled'] == true,
      pairCode: json['pairCode']?.toString(),
      expiresIn: json['expiresIn'],
      apps: json['apps'],
      wallpaper: json['wallpaper'],
      shellSupported:
          json['shellSupported'] == true ||
          json['shellSupported'] == 1 ||
          json['shellSupported'] == '1',
      serverVersion: json['serverVersion']?.toString(),
    );
  }
  @override
  String toString() {
    return 'LoginResponse{success: $success, message: $message, accessToken: $accessToken, refreshToken: $refreshToken, user: $user, twoFactorRequired: $twoFactorRequired, tempToken: $tempToken, platform: $platform, hostname: $hostname, serverId: $serverId, httpPort: $httpPort, httpsPort: $httpsPort, lanIpv4: $lanIpv4, p2pRemoteAccessEnabled: $p2pRemoteAccessEnabled, pairCode: $pairCode, expiresIn: $expiresIn, apps: $apps, wallpaper: $wallpaper, shellSupported: $shellSupported}';
  }
}
