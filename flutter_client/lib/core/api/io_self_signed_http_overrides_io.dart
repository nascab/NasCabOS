import 'dart:io';

import 'proxy_bypass_config.dart';

/// 使 [Image.network]、[ExtendedImage.network] 等使用默认 [HttpClient] 的路径与 API 层一致，可访问自签名 HTTPS。
void applyIoSelfSignedHttpOverridesIfNeeded() {
  HttpOverrides.global = _NasCabSelfSignedHttpOverrides();
}

class _NasCabSelfSignedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    c.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    // 覆盖所有裸 HttpClient()（含 WebSocket、Dio 默认适配器）：
    // 连接时动态判断是否忽略本地代理（DIRECT），未勾选保持 Dart 默认行为
    c.findProxy = (Uri uri) => ProxyBypassConfig.enabled
        ? 'DIRECT'
        : HttpClient.findProxyFromEnvironment(uri);
    return c;
  }
}
