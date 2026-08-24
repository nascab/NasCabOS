import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart';

/// Web 端：使用 HtmlWebSocketChannel 并设置 binaryType，使服务端发的二进制帧以 ByteBuffer 形式收到，
/// 否则浏览器默认会以 Blob 下发，decodeSignalingFromEvent 无法解析，导致收不到 session:ready。
WebSocketChannel createP2pWebSocketChannel(Object uri, Object? customClient) {
  return HtmlWebSocketChannel.connect(uri, binaryType: BinaryType.list);
}
