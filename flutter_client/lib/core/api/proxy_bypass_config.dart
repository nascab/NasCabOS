/// “忽略本地代理”全局配置。
///
/// Dart VM 的 [HttpClient] 默认使用 `findProxyFromEnvironment`
/// 解析 http_proxy/https_proxy/no_proxy 环境变量；启用后所有网络请求
/// 强制 DIRECT 直连（见 core/api 下各 IO 网络工厂中的 findProxy 闭包，
/// 闭包在每次建立连接时动态读取本标志，切换后对已存在的客户端同样生效）。
class ProxyBypassConfig {
  ProxyBypassConfig._();

  /// 本地缓存键（SharedPreferences）
  static const String cacheKey = 'ignore_local_proxy';

  /// 是否让所有网络请求忽略本地代理（强制直连），默认开启
  static bool enabled = true;
}
