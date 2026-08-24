/// Web 等非 dart:io 平台占位；桌面端请使用 `nascab_desktop_oauth_io.dart`。
Future<NasCabDesktopOAuthSession> startNasCabDesktopOAuthSession({
  Duration timeout = const Duration(minutes: 5),
  required String language,
}) {
  throw UnsupportedError('NasCab desktop OAuth callback is only for dart:io targets');
}

class NasCabDesktopOAuthSession {
  String get redirectUrl =>
      throw UnsupportedError('NasCab desktop OAuth callback is only for dart:io targets');

  Future<Map<String, String>?> get result =>
      throw UnsupportedError('NasCab desktop OAuth callback is only for dart:io targets');

  Future<void> shutdown() =>
      throw UnsupportedError('NasCab desktop OAuth callback is only for dart:io targets');
}
