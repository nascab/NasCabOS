import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_controller.dart';

WebSocketChannel connectFileWebSocketChannel(Uri uri) {
  final base = ApiController.instance.baseUrl.trim();
  if (base == ApiController.p2pBaseUrl ||
      base.startsWith('${ApiController.p2pBaseUrl}/')) {
    return ApiController.instance.connectP2pWebSocketChannelLazy(uri);
  }
  final client = HttpClient();
  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) => true;
  return IOWebSocketChannel.connect(uri, customClient: client);
}
