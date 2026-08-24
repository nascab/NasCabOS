import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/api/api_controller.dart';
import 'file_stats_service.dart';

class FileWatcherService {
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;

  // Callback for when file changes are received
  final Function(Map<String, dynamic>)? onFileChange;
  final Function(Object)? onError;

  FileWatcherService({this.onFileChange, this.onError});

  void connect(String path) {
    disconnect();

    final baseUrl = ApiController.instance.baseUrl;
    if (baseUrl.isEmpty) return;

    final wsBaseUri = resolveFileWsBaseUri(baseUrl);
    if (wsBaseUri.host.isEmpty) return;

    // 添加参数
    final token = ApiController.instance.accessToken;
    final queryParameters = <String, dynamic>{};
    if (token != null) {
      queryParameters['accessToken'] = token;
    }
    queryParameters['path'] = path;

    final wsUri = buildFileWebSocketUri(
      wsBaseUri: wsBaseUri,
      path: '/api/file/watch',
      queryParameters: queryParameters,
    );
    print("wsUri: $wsUri");
    try {
      _wsChannel = connectFileWebSocket(wsUri);

      // Listen
      _wsSub = _wsChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'change' && onFileChange != null) {
              onFileChange!(data);
            }
          } catch (e) {
            print('WS Parse Error: $e');
          }
        },
        onError: (e) {
          print('WS Error: $e');
          if (onError != null) onError!(e);
        },
      );

      // Send watch command
      _wsChannel!.sink.add(jsonEncode({'type': 'watch', 'path': path}));
    } catch (e) {
      print('WS Connect Error: $e');
      if (onError != null) onError!(e);
    }
  }

  void disconnect() {
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _wsSub = null;
    _wsChannel = null;
  }
}
