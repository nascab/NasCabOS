import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/api/api_controller.dart';

WebSocketChannel connectFileWebSocketChannel(Uri uri) {
  final base = ApiController.instance.baseUrl.trim();
  if (base == ApiController.p2pBaseUrl ||
      base.startsWith('${ApiController.p2pBaseUrl}/')) {
    return ApiController.instance.connectP2pWebSocketChannelLazy(uri);
  }
  return WebSocketChannel.connect(uri);
}
