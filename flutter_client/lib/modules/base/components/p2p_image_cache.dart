import 'dart:typed_data';

// Web / 无 IO 环境：P2P 图片不落盘，仅内存
Future<Uint8List?> readP2pImageCache(String cacheKey) async => null;
Future<void> writeP2pImageCache(String cacheKey, Uint8List bytes) async {}
