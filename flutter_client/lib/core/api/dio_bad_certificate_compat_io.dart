import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'proxy_bypass_config.dart';

/// 与 [http_client_factory_io.dart] 一致：允许连接使用自签名证书的 HTTPS 服务。
void configureDioBadCertificateCompat(Dio client) {
  client.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final c = HttpClient();
      c.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      // 连接时动态判断：勾选“忽略本地代理”强制 DIRECT；未勾选时回环地址
      // （127.x/localhost/::1）仍 DIRECT 直连，其余保持 Dart 默认代理行为
      c.findProxy = (Uri uri) =>
          ProxyBypassConfig.enabled || ProxyBypassConfig.isLoopbackUri(uri)
              ? 'DIRECT'
              : HttpClient.findProxyFromEnvironment(uri);
      return c;
    },
  );
}
