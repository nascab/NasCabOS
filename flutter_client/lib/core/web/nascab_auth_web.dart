import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// 返回 [Map] 含 `code` 或 `jwt` 其一，供登录流程使用（code 优先，避免 JWT 暴露在 URL）
Future<Map<String, String>?> openNasCabAuthPopup(
  String url, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final origin = web.window.location.origin;
  final popup = web.window.open(
    url,
    'nascab_login_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}',
  );
  if (popup == null) return null;

  final completer = Completer<Map<String, String>?>();
  StreamSubscription<web.MessageEvent>? sub;
  Timer? timeoutTimer;
  Timer? closedPollTimer;
  Timer? _graceTimer;

  void cleanup() {
    timeoutTimer?.cancel();
    closedPollTimer?.cancel();
    _graceTimer?.cancel();
    timeoutTimer = null;
    closedPollTimer = null;
    _graceTimer = null;
    sub?.cancel();
    sub = null;
    try {
      popup.close();
    } catch (_) {}
  }

  void completeWith(Map<String, String>? result) {
    if (completer.isCompleted) return;
    cleanup();
    completer.complete(result);
  }

  timeoutTimer = Timer(timeout, () => completeWith(null));

  closedPollTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
    try {
      if (popup.closed == true) {
        closedPollTimer?.cancel();
        closedPollTimer = null;
        // 延迟 500ms 再判定为取消，给 postMessage 事件留出处理窗口
        _graceTimer = Timer(const Duration(milliseconds: 500), () => completeWith(null));
      }
    } catch (_) {}
  });

  sub = web.EventStreamProviders.messageEvent.forTarget(web.window).listen((
    msg,
  ) {
    if (msg.origin != origin) return;
    final data = msg.data?.toString() ?? '';
    if (data.isEmpty) return;
    Map<String, dynamic>? decoded;
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic>) decoded = json;
    } catch (_) {}
    if (decoded == null) return;
    final type = decoded['type']?.toString() ?? '';
    if (type == 'nascab_auth') {
      final code = (decoded['code']?.toString() ?? '').trim();
      final jwt = (decoded['jwt']?.toString() ?? '').trim();
      if (code.isNotEmpty) {
        completeWith({'code': code});
        return;
      }
      if (jwt.isNotEmpty) {
        completeWith({'jwt': jwt});
        return;
      }
      return;
    }
    if (type == 'nascab_jwt') {
      final jwt = (decoded['jwt']?.toString() ?? '').trim();
      if (jwt.isNotEmpty) completeWith({'jwt': jwt});
    }
  });

  return completer.future;
}

void sendJwtToOpenerAndClose(String jwt) {
  sendAuthResultToOpenerAndClose({'jwt': jwt});
}

void sendAuthResultToOpenerAndClose(Map<String, String> result) {
  final opener = web.window.opener;
  if (opener != null) {
    try {
      final openerWindow = opener as web.Window;
      openerWindow.postMessage(
        jsonEncode({'type': 'nascab_auth', ...result}).toJS,
        web.window.location.origin.toJS,
      );
    } catch (_) {}
  }
  // 延迟关闭，确保 postMessage 有时间被浏览器事件循环分发到 opener
  Timer(const Duration(milliseconds: 300), () {
    try {
      web.window.close();
    } catch (_) {}
  });
}
