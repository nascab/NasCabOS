import 'package:web/web.dart' as web;

String getWebUserAgent() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}
