import 'dart:async';
import 'dart:io';

import 'nascab_desktop_oauth_callback_i18n.dart';

const _callbackPath = '/nascab-callback';

/// 在本机回环地址启动临时 HTTP 服务，供登录页 redirect 携带 <code>code</code> 或 <code>jwt</code>。
///
/// [language] 为应用当前语言码（与 [LanguageService.currentLocale] 一致），会写入
/// `redirect_url` 的查询参数 `language`，回调页据此展示文案。
///
/// 登录成功后 [complete] 会立即 [closeServer]，停止接受新连接。
Future<NasCabDesktopOAuthSession> startNasCabDesktopOAuthSession({
  Duration timeout = const Duration(minutes: 5),
  required String language,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  final langKey = NasCabDesktopOAuthCallbackI18n.normalizeLanguageParam(language);
  final redirectUrl = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: port,
    path: _callbackPath,
    queryParameters: {'language': langKey},
  ).toString();
  final completer = Completer<Map<String, String>?>();
  Timer? timeoutTimer;
  var closed = false;

  Future<void> closeServer() async {
    if (closed) return;
    closed = true;
    timeoutTimer?.cancel();
    timeoutTimer = null;
    try {
      await server.close(force: true);
    } catch (_) {}
  }

  void complete(Map<String, String>? value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    unawaited(closeServer());
  }

  timeoutTimer = Timer(timeout, () => complete(null));

  server.listen(
    (HttpRequest request) async {
      final p = request.uri.path;
      if (p != _callbackPath && p != '$_callbackPath/') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code']?.trim() ?? '';
      final jwt = request.uri.queryParameters['jwt']?.trim() ?? '';
      final langParam = request.uri.queryParameters['language'];

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType(
        'text',
        'html',
        charset: 'utf-8',
      );
      request.response.write(
        NasCabDesktopOAuthCallbackI18n.buildSuccessHtml(
          NasCabDesktopOAuthCallbackI18n.normalizeLanguageParam(langParam),
        ),
      );
      await request.response.close();

      if (code.isNotEmpty) {
        complete({'code': code});
      } else if (jwt.isNotEmpty) {
        complete({'jwt': jwt});
      } else {
        complete(null);
      }
    },
    onError: (_) => complete(null),
    cancelOnError: false,
  );

  Future<void> shutdown() async {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
    await closeServer();
  }

  return NasCabDesktopOAuthSession._(
    redirectUrl: redirectUrl,
    resultFuture: completer.future,
    shutdown: shutdown,
  );
}

class NasCabDesktopOAuthSession {
  NasCabDesktopOAuthSession._({
    required this.redirectUrl,
    required Future<Map<String, String>?> resultFuture,
    required Future<void> Function() shutdown,
  })  : _resultFuture = resultFuture,
        _shutdown = shutdown;

  final String redirectUrl;
  final Future<Map<String, String>?> _resultFuture;
  final Future<void> Function() _shutdown;

  Future<Map<String, String>?> get result => _resultFuture;

  Future<void> shutdown() => _shutdown();
}
