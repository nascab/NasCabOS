/// 与 [LanguageService.supportedLocales] 一致的 13 种语言，用于本地 OAuth 回调页 HTML。
class NasCabDesktopOAuthCallbackI18n {
  NasCabDesktopOAuthCallbackI18n._();

  static const Set<String> supportedKeys = {
    'zh_CN',
    'en_US',
    'fr_FR',
    'de_DE',
    'pt_BR',
    'ja_JP',
    'ru_RU',
    'th_TH',
    'ko_KR',
    'es_ES',
    'ar_AR',
    'vi_VN',
    'id_ID',
  };

  /// 将 GET 参数 `language`（如 zh_CN、zh-cn）规范为 supportedKeys 之一，否则 en_US。
  static String normalizeLanguageParam(String? raw) {
    if (raw == null) return 'en_US';
    final t = raw.trim().replaceAll('-', '_');
    if (t.isEmpty) return 'en_US';
    for (final k in supportedKeys) {
      if (k.toLowerCase() == t.toLowerCase()) return k;
    }
    return 'en_US';
  }

  static String htmlLangBcp47(String key) {
    final parts = key.split('_');
    if (parts.length == 2) {
      return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
    }
    return parts[0].toLowerCase();
  }

  static bool isRtl(String key) => key == 'ar_AR';

  static const Map<String, ({String title, String body})> _strings = {
    'zh_CN': (
      title: '登录成功',
      body: '您可以关闭此页面并返回 NasCab 客户端。',
    ),
    'en_US': (
      title: 'Sign-in successful',
      body: 'You can close this page and return to the NasCab app.',
    ),
    'fr_FR': (
      title: 'Connexion réussie',
      body:
          'Vous pouvez fermer cette page et revenir à l’application NasCab.',
    ),
    'de_DE': (
      title: 'Anmeldung erfolgreich',
      body:
          'Sie können diese Seite schließen und zur NasCab-App zurückkehren.',
    ),
    'pt_BR': (
      title: 'Login concluído',
      body: 'Você pode fechar esta página e voltar ao aplicativo NasCab.',
    ),
    'ja_JP': (
      title: 'ログインしました',
      body: 'このページを閉じて NasCab アプリに戻ってください。',
    ),
    'ru_RU': (
      title: 'Вход выполнен',
      body: 'Закройте эту страницу и вернитесь в приложение NasCab.',
    ),
    'th_TH': (
      title: 'เข้าสู่ระบบสำเร็จ',
      body: 'คุณสามารถปิดหน้านี้และกลับไปที่แอป NasCab',
    ),
    'ko_KR': (
      title: '로그인되었습니다',
      body: '이 페이지를 닫고 NasCab 앱으로 돌아가세요.',
    ),
    'es_ES': (
      title: 'Sesión iniciada',
      body: 'Puede cerrar esta página y volver a la aplicación NasCab.',
    ),
    'ar_AR': (
      title: 'تم تسجيل الدخول',
      body: 'يمكنك إغلاق هذه الصفحة والعودة إلى تطبيق NasCab.',
    ),
    'vi_VN': (
      title: 'Đăng nhập thành công',
      body: 'Bạn có thể đóng trang này và quay lại ứng dụng NasCab.',
    ),
    'id_ID': (
      title: 'Login berhasil',
      body: 'Anda dapat menutup halaman ini dan kembali ke aplikasi NasCab.',
    ),
  };

  static String buildSuccessHtml(String localeKey) {
    final key = supportedKeys.contains(localeKey)
        ? localeKey
        : normalizeLanguageParam(localeKey);
    final s = _strings[key] ?? _strings['en_US']!;
    final htmlLang = htmlLangBcp47(key);
    final dir = isRtl(key) ? 'rtl' : 'ltr';
    return '''
<!DOCTYPE html>
<html lang="$htmlLang" dir="$dir">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta name="color-scheme" content="dark"/>
  <title>${_escapeHtml(s.title)} · NasCab</title>
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #121218;
      color: #ececf1;
      padding: 24px 16px;
      -webkit-font-smoothing: antialiased;
    }
    .card {
      width: 100%;
      max-width: 440px;
      background: #1e1e26;
      border-radius: 16px;
      padding: 32px 28px;
      border: 1px solid rgba(255,255,255,0.08);
      box-shadow: 0 12px 40px rgba(0,0,0,0.45);
    }
    h1 {
      font-size: 1.35rem;
      font-weight: 600;
      margin: 0 0 14px;
      color: #f4f4f6;
      letter-spacing: -0.02em;
    }
    p {
      margin: 0;
      line-height: 1.65;
      color: #a8a8b3;
      font-size: 0.95rem;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>${_escapeHtml(s.title)}</h1>
    <p>${_escapeHtml(s.body)}</p>
  </div>
</body>
</html>
''';
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
