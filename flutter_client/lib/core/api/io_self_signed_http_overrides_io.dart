import 'dart:io';

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
    return c;
  }
}
