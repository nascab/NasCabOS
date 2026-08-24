import 'package:dio/dio.dart';

import 'dio_bad_certificate_compat_io.dart'
    if (dart.library.html) 'dio_bad_certificate_compat_web.dart' as impl;

/// 在 VM 平台上为 [Dio] 配置接受自签名/不受信任证书的 [HttpClient]。
void configureDioBadCertificateCompat(Dio client) {
  impl.configureDioBadCertificateCompat(client);
}

/// 新建已按平台配置 TLS 的 [Dio]（VM 上与 [createHttpClient] 一致，允许自签名 HTTPS）。
Dio createDioWithBadCertificateCompat([BaseOptions? options]) {
  final d = Dio(options ?? BaseOptions());
  configureDioBadCertificateCompat(d);
  return d;
}
