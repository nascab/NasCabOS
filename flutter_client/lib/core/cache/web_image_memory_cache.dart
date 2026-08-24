import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Web端专用内存缓存管理器
/// 策略：LRU (Least Recently Used)
/// 限制：最大1000个对象，单张图片最大500KB，总缓存最大500MB
class WebImageMemoryCache {
  static final WebImageMemoryCache _instance = WebImageMemoryCache._internal();
  factory WebImageMemoryCache() => _instance;
  WebImageMemoryCache._internal();

  // 最大缓存数量
  static const int _maxCount = 1000;
  // 单张图片最大大小 (500KB)
  static const int _maxSizeBytes = 500 * 1024;
  // 总缓存最大大小 (200MB)
  static const int _maxTotalSizeBytes = 200 * 1024 * 1024;

  // 当前总缓存大小
  int _currentTotalSize = 0;

  // 使用 LinkedHashMap 实现 LRU
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  Uint8List? get(String url) {
    final data = _cache[url];
    if (data != null) {
      // 命中缓存，将其移动到末尾（表示最近使用）
      _cache.remove(url);
      _cache[url] = data;
    }
    return data;
  }

  void put(String url, Uint8List bytes) {
    // 检查图片大小，超过限制则不缓存
    if (bytes.lengthInBytes > _maxSizeBytes) {
      debugPrint(
        'WebImageCache: Image too large (${bytes.lengthInBytes} bytes), skipping cache. URL: $url',
      );
      return;
    }

    // 如果已存在，先移除（为了更新位置和重新计算大小）
    if (_cache.containsKey(url)) {
      final removed = _cache.remove(url);
      if (removed != null) {
        _currentTotalSize -= removed.lengthInBytes;
      }
    }

    // 检查容量：如果达到最大数量 OR 加上新图片后会超过总大小限制，则移除最早的元素
    while ((_cache.length >= _maxCount ||
            _currentTotalSize + bytes.lengthInBytes > _maxTotalSizeBytes) &&
        _cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      final removed = _cache.remove(firstKey);
      if (removed != null) {
        _currentTotalSize -= removed.lengthInBytes;
      }
    }

    // 只有在有足够空间时才添加（理论上只要 _maxSizeBytes < _maxTotalSizeBytes 且缓存为空时一定能添加，但加个判断更安全）
    if (_currentTotalSize + bytes.lengthInBytes <= _maxTotalSizeBytes) {
      _cache[url] = bytes;
      _currentTotalSize += bytes.lengthInBytes;
    } else {
      debugPrint(
        'WebImageCache: Cache full, cannot add image even after clearing. URL: $url',
      );
    }
  }

  void clear() {
    _cache.clear();
    _currentTotalSize = 0;
  }
}
