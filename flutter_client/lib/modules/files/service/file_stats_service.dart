import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/api/api_controller.dart';
import 'file_ws_channel_factory_stub.dart'
    if (dart.library.io) 'file_ws_channel_factory_io.dart';

/// 解析文件 WebSocket 的 base Uri，与终端 getTerminalConnectUrl 逻辑一致：
/// Web 端开发模式下用服务器 baseUrl（如 127.0.0.1:9000），否则用地址栏；非 Web 端用登录返回的 httpsPort（有则 wss+该端口，否则用 baseUrl 的端口）。
Uri resolveFileWsBaseUri(String baseUrl) {
  final base = baseUrl.trim();
  if (base.isEmpty) return Uri();

  if (kIsWeb) {
    if (kDebugMode && base.isNotEmpty) {
      final baseUri = Uri.tryParse(base);
      if (baseUri == null || baseUri.host.isEmpty) return Uri();
      final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
      final port = baseUri.hasPort
          ? baseUri.port
          : (scheme == 'wss' ? 443 : 80);
      return Uri(scheme: scheme, host: baseUri.host, port: port, path: '');
    }
    final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
    final port = Uri.base.hasPort
        ? Uri.base.port
        : (scheme == 'wss' ? 443 : 80);
    return Uri(scheme: scheme, host: Uri.base.host, port: port, path: '');
  }

  final baseUri = Uri.tryParse(base);
  if (baseUri == null) return Uri();
  final httpsPortStr = (ApiController.instance.state.httpsPort ?? '').trim();
  if (httpsPortStr.isNotEmpty) {
    final port = int.tryParse(httpsPortStr) ?? 443;
    return baseUri.replace(
      scheme: 'wss',
      port: port,
      path: '',
      query: '',
      fragment: null,
    );
  }
  // 直连 HTTP（如 http://ip:9000）时必须用 ws，否则 wss 会在明文端口上做 TLS 握手 → WRONG_VERSION_NUMBER
  final useTls = baseUri.scheme == 'https';
  final wsScheme = useTls ? 'wss' : 'ws';
  final port = baseUri.hasPort
      ? baseUri.port
      : (useTls ? 443 : 80);
  return baseUri.replace(
    scheme: wsScheme,
    port: port,
    path: '',
    query: '',
    fragment: null,
  );
}

Uri buildFileWebSocketUri({
  required Uri wsBaseUri,
  required String path,
  required Map<String, dynamic> queryParameters,
}) {
  return wsBaseUri.replace(path: path, queryParameters: queryParameters);
}

WebSocketChannel connectFileWebSocket(Uri uri) {
  return connectFileWebSocketChannel(uri);
}

class FileStats {
  final int size;
  final int count;
  final int folderCount;
  final DateTime? ctime;
  final DateTime? mtime;
  final String? name;
  final String? path;

  FileStats({
    this.size = 0,
    this.count = 0,
    this.folderCount = 0,
    this.ctime,
    this.mtime,
    this.name,
    this.path,
  });

  /// Node `JSON.stringify(Date)` 为带 Z 的 UTC ISO 字符串；解析后需转本地再展示。
  static DateTime? _parseToLocal(dynamic value) {
    if (value == null) return null;
    final d = DateTime.tryParse(value.toString());
    return d?.toLocal();
  }

  factory FileStats.fromJson(Map<String, dynamic> json) {
    return FileStats(
      size: json['size'] ?? 0,
      count: json['count'] ?? 0,
      folderCount: json['folderCount'] ?? 0,
      ctime: _parseToLocal(json['ctime']),
      mtime: _parseToLocal(json['mtime']),
      name: json['name'],
      path: json['path'],
    );
  }
}

class FileStatsService {
  WebSocketChannel? _channel;
  Function(FileStats stats)? _onProgress;
  Function(FileStats stats)? _onComplete;
  Function(String error)? _onError;

  void connect({
    required List<String> paths,
    Function(FileStats stats)? onProgress,
    Function(FileStats stats)? onComplete,
    Function(String error)? onError,
  }) {
    _onProgress = onProgress;
    _onComplete = onComplete;
    _onError = onError;

    final baseUrl = ApiController.instance.baseUrl;
    if (baseUrl.isEmpty) {
      _onError?.call('Base URL is empty');
      return;
    }

    final wsBaseUri = resolveFileWsBaseUri(baseUrl);
    if (wsBaseUri.host.isEmpty) {
      _onError?.call('Invalid Base URL');
      return;
    }

    // Add token
    final token = ApiController.instance.accessToken;
    final queryParameters = <String, dynamic>{};
    if (token != null) {
      queryParameters['accessToken'] = token;
    }

    final wsUri = buildFileWebSocketUri(
      wsBaseUri: wsBaseUri,
      path: '/api/file/stats',
      queryParameters: queryParameters,
    );

    try {
      _channel = connectFileWebSocket(wsUri);
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          final type = data['type'];
          if (type == 'progress') {
            _onProgress?.call(FileStats.fromJson(data));
          } else if (type == 'complete') {
            _onComplete?.call(FileStats.fromJson(data));
            close();
          } else if (type == 'error') {
            _onError?.call(data['message']);
            close();
          }
        },
        onError: (e) {
          _onError?.call(e.toString());
        },
        onDone: () {
          // Closed
        },
      );

      _channel!.sink.add(jsonEncode({'paths': paths, 'action': 'start'}));
    } catch (e) {
      _onError?.call(e.toString());
    }
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
