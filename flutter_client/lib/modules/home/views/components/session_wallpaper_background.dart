import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../base/components/custom_extended_image.dart';

/// 桌面/主页壁纸：随登录会话（serverId、baseUrl）与壁纸配置变化而刷新。
///
/// 壁纸接口仅校验 Authorization Bearer，不使用 URL 中的 aes 参数；
/// 因此这里使用 [ApiController.getWallpaperResolvedUrl] 并在请求时附带当前 token。
class SessionWallpaperBackground extends StatelessWidget {
  const SessionWallpaperBackground({
    super.key,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final BoxFit fit;
  final Widget? placeholder;

  /// 登录成功后预加载当前会话壁纸，避免进入桌面时首帧请求失败卡在 404。
  static Future<void> preloadForCurrentSession() async {
    final api = ApiController.instance;
    if (!api.state.isAuthenticated) return;
    final url = api.getWallpaperResolvedUrl();
    if (url == null || url.isEmpty) return;
    try {
      await CustomExtendedImage.preload(url);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final api = ApiController.instance;
      final channelRevision = api.connectChannelRevision.value;
      CurrentUserController.instance.wallpaper;

      if (!api.state.isAuthenticated) {
        return placeholder ?? const SizedBox.shrink();
      }

      final url = api.getWallpaperResolvedUrl();
      if (url == null || url.isEmpty) {
        return placeholder ?? const SizedBox.shrink();
      }

      return _SessionWallpaperImage(
        key: ValueKey('session_wallpaper:$url'),
        imageUrl: url,
        channelRevision: channelRevision,
        fit: fit,
        placeholder: placeholder,
      );
    });
  }
}

/// 切换 URL 时保留上一帧壁纸；连接通道变更或首帧失败时自动重试，避免 404 占位卡住。
///
/// 双 token 设计：
/// - [_prevToken] 仅在 URL 变化时递增，保证旧层在 channel 切换时不被重建
/// - [_loadToken] 在 URL 或 channel 变化时递增，驱动新层重新加载
/// - [_cachedBytes] 缓存最后一次成功加载的图片字节，作为无网/失败时的兜底
class _SessionWallpaperImage extends StatefulWidget {
  const _SessionWallpaperImage({
    super.key,
    required this.imageUrl,
    required this.channelRevision,
    required this.fit,
    this.placeholder,
  });

  final String imageUrl;
  final int channelRevision;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  State<_SessionWallpaperImage> createState() => _SessionWallpaperImageState();
}

class _SessionWallpaperImageState extends State<_SessionWallpaperImage> {
  String? _previousUrl;
  int _prevToken = 0;
  int _loadToken = 0;
  Uint8List? _cachedBytes;

  @override
  void didUpdateWidget(covariant _SessionWallpaperImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _previousUrl = oldWidget.imageUrl;
      _prevToken++;
      _loadToken++;
    } else if (oldWidget.channelRevision != widget.channelRevision) {
      _loadToken++;
    }
  }

  void _onImageLoaded(Uint8List bytes) {
    _cachedBytes = bytes;
  }

  Widget _buildLayer(String url, int token, {bool isCurrent = false}) {
    return _WallpaperImage(
      key: ValueKey('wallpaper_layer:$url#$token'),
      imageUrl: url,
      fit: widget.fit,
      placeholder: widget.placeholder,
      cachedBytes: _cachedBytes,
      onLoaded: isCurrent ? _onImageLoaded : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_previousUrl != null) _buildLayer(_previousUrl!, _prevToken),
        _buildLayer(widget.imageUrl, _loadToken, isCurrent: true),
      ],
    );
  }
}

class _WallpaperImage extends StatefulWidget {
  const _WallpaperImage({
    super.key,
    required this.imageUrl,
    required this.fit,
    this.placeholder,
    this.cachedBytes,
    this.onLoaded,
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Uint8List? cachedBytes;
  final void Function(Uint8List bytes)? onLoaded;

  @override
  State<_WallpaperImage> createState() => _WallpaperImageState();
}

class _WallpaperImageState extends State<_WallpaperImage> {
  static const _maxAttempts = 4;

  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant _WallpaperImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _startLoad();
    }
  }

  void _startLoad() {
    _future = _loadWithRetry(widget.imageUrl);
  }

  Future<Uint8List> _loadWithRetry(String url) async {
    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << (attempt - 1))),
        );
      }
      try {
        final bytes = await CustomExtendedImage.getOrCreateLoadFuture(url);
        if (bytes.isNotEmpty) {
          widget.onLoaded?.call(bytes);
          return bytes;
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('wallpaper_load_failed');
  }

  /// 优先展示缓存字节（上次成功加载的壁纸），其次展示 placeholder
  Widget _buildFallback() {
    final cached = widget.cachedBytes;
    if (cached != null && cached.isNotEmpty) {
      return _buildImage(cached);
    }
    return widget.placeholder ?? const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    if (future == null) {
      return _buildFallback();
    }

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildFallback();
        }
        if (snapshot.hasError) {
          return _buildFallback();
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildFallback();
        }
        return _buildImage(bytes);
      },
    );
  }

  Widget _buildImage(Uint8List bytes) {
    return Image.memory(
      bytes,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
  }
}
