import 'package:web/web.dart' as web;

/// Web 平台：通过浏览器获取当前页面的 hostname，
/// 用于同机检测中 localhost 探测被 CORS 阻挡时的 fallback。
String getLocalBrowserHostname() {
  try {
    return web.window.location.hostname;
  } catch (_) {
    return '';
  }
}
