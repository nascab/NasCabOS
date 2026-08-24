import 'package:web/web.dart' as web;

Future<String?> kvGet(String key) async {
  return web.window.localStorage.getItem(key);
}

Future<void> kvSet(String key, String? value) async {
  if (value == null) {
    web.window.localStorage.removeItem(key);
    return;
  }
  web.window.localStorage.setItem(key, value);
}
