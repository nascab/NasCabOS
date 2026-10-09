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
    // 连接时动态判断是否忽略本地代理（DIRECT）；未勾选时回环地址
    // （127.x/localhost/::1）仍 DIRECT 直连，其余保持 Dart 默认代理行为
    c.findProxy = (Uri uri) =>
        ProxyBypassConfig.enabled || ProxyBypassConfig.isLoopbackUri(uri)
            ? 'DIRECT'
            : HttpClient.findProxyFromEnvironment(uri);
    return c;
  }
}
