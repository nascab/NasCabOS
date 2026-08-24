import 'package:dio/dio.dart';

/// Web 端 TLS 由浏览器校验，无法在此绕过证书错误。
void configureDioBadCertificateCompat(Dio client) {}
