import 'dart:typed_data';

/// Web：不落盘，读恒为 null，写为空操作
Future<Uint8List?> readMapTileCache(String cacheKey) async => null;
Future<void> writeMapTileCache(String cacheKey, Uint8List bytes) async {}
Future<void> clearMapTileCache() async {}
