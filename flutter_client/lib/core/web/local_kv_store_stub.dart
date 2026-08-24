import 'package:shared_preferences/shared_preferences.dart';

Future<String?> kvGet(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(key);
}

Future<void> kvSet(String key, String? value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value == null) {
    await prefs.remove(key);
    return;
  }
  await prefs.setString(key, value);
}
