import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'proxy_bypass_config.dart';

http.Client createHttpClient() {
  final ioClient = HttpClient();
  ioClient.badCertificateCallback =
      (X509Certificate cert, String host, int port) => true;
  // 连接时动态判断：勾选“忽略本地代理”强制 DIRECT，未勾选保持 Dart 默认行为
  ioClient.findProxy = (Uri uri) => ProxyBypassConfig.enabled
      ? 'DIRECT'
      : HttpClient.findProxyFromEnvironment(uri);
  return IOClient(ioClient);
}
