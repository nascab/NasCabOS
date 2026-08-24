import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 与 [http_client_factory_io.dart] 一致：允许连接使用自签名证书的 HTTPS 服务。
void configureDioBadCertificateCompat(Dio client) {
  client.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final c = HttpClient();
      c.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return c;
    },
  );
}
