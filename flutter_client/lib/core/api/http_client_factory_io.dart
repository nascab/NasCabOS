import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'proxy_bypass_config.dart';

http.Client createHttpClient() {
  final ioClient = HttpClient();
  ioClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) => true;
  // 连接时动态判断：勾选“忽略本地代理”强制 DIRECT；未勾选时回环地址
  // （127.x/localhost/::1）仍 DIRECT 直连，其余保持 Dart 默认代理行为
  ioClient.findProxy = (Uri uri) =>
      ProxyBypassConfig.enabled || ProxyBypassConfig.isLoopbackUri(uri)
          ? 'DIRECT'
          : HttpClient.findProxyFromEnvironment(uri);
  return IOClient(ioClient);
}
