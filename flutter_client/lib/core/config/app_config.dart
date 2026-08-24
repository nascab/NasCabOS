/// 应用配置常量管理类
class AppConfig {
  /// 本地NasCab服务器API基础URL
  static const String localhostBaseUrl = 'http://127.0.0.1:6789';

  /// 远程NasCab服务器API基础URL（预留）
  static const String remoteNasCabApiBaseUrl = 'https://api.nascab.com';

  /// 默认API超时时间（秒）
  static const int defaultApiTimeoutSeconds = 15;

  /// 默认重试次数
  static const int defaultMaxRetries = 2;

  /// 检查是否为NasCab服务器接口路径
  static const String urlIsNasCabServer = '/api/auth/isNasCabServer';
}
