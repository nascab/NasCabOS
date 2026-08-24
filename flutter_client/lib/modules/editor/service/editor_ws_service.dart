import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/api/api_controller.dart';
import '../../files/service/file_stats_service.dart';

class EditorWsService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  Future<void> connect({
    required String filePath,
    required void Function(Map<String, dynamic> msg) onMessage,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    disconnect();

    final baseUrl = ApiController.instance.baseUrl;
    if (baseUrl.isEmpty) {
      if (onError != null) onError(StateError('baseUrl is empty'));
      return;
    }

    final wsBaseUri = resolveFileWsBaseUri(baseUrl);
    if (wsBaseUri.host.isEmpty) {
      if (onError != null) onError(StateError('invalid baseUrl'));
      return;
    }

    var token = ApiController.instance.accessToken?.trim() ?? '';
    if (token.isEmpty) {
      try {
        await ApiController.instance.refreshAuthToken();
      } catch (_) {}
      token = ApiController.instance.accessToken?.trim() ?? '';
    }

    final queryParameters = <String, dynamic>{'path': filePath};
    if (token.isNotEmpty) {
      queryParameters['accessToken'] = token;
    }

    final wsUri = buildFileWebSocketUri(
      wsBaseUri: wsBaseUri,
      path: '/api/editor/ws',
      queryParameters: queryParameters,
    );

    try {
      _channel = connectFileWebSocket(wsUri);
      _sub = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data is Map<String, dynamic>) {
              onMessage(data);
            }
          } catch (_) {}
        },
        onError: (e) {
          if (onError != null) onError(e);
        },
        onDone: () {
          if (onDone != null) onDone();
        },
      );
    } catch (e) {
      if (onError != null) onError(e);
    }
    return;
  }

  void send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }
}
