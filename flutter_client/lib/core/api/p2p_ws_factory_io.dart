import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 原生/桌面端：使用 IOWebSocketChannel，二进制帧会以 `List<int>` / `ByteBuffer` 形式收到。
WebSocketChannel createP2pWebSocketChannel(Uri uri, HttpClient? customClient) {
  return IOWebSocketChannel.connect(uri, customClient: customClient);
}
