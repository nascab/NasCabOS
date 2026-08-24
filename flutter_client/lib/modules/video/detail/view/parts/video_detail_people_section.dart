import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../../../../core/api/api_controller.dart';
import '../../../../../utils/device_utils.dart';
import '../../../home/view/parts/video_horizontal_scroller.dart';
import '../../../list/view/app_video_person_videos_page.dart';
import '../../controller/video_detail_controller.dart';
import '../../../video_main/controller/video_main_controller.dart';

/// 演职人员区：导演与演员列表。
class VideoDetailPeopleSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailPeopleSection({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirs = ctrl.directors;
    final acts = ctrl.actors;
    final rawMediaType = (ctrl.item?['media_type']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final resolvedMediaType = rawMediaType == 'season' ? 'tv' : rawMediaType;

    if (dirs.isEmpty && acts.isEmpty) {
      return const SizedBox.shrink();
    }

    final people = <Map<String, dynamic>>[
      ...dirs.map((e) => {...e, '_role': 'video_detail_directors'.tr}),
      ...acts.map((e) => {...e, '_role': 'video_detail_actors'.tr}),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('video_detail_people'.tr, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        VideoHorizontalScroller(
          height: 220,
          children: [
            ...people.map((p) {
              final name = (p['name']?.toString() ?? '').trim();
              final role = (p['_role']?.toString() ?? '').trim();
              final tmdbId = (p['tmdbId']?.toString() ?? '').trim();
              final thumb = (p['thumb']?.toString() ?? '').trim();
              final url = tmdbId.isNotEmpty
                  ? ApiController.instance.getVideoPersonImageUrl(
                      tmdbId: tmdbId,
                      size: 240,
                      thumb: thumb.isNotEmpty ? thumb : null,
                    )
                  : '';

              void openOverlay() {
                if (name.isEmpty) return;
                final isDirector = role == 'video_detail_directors'.tr;
                if (DeviceUtils.isMobile) {
                  Get.to(
                    () => isDirector
                        ? AppVideoPersonVideosPage.director(
                            name: name,
                            mediaType: resolvedMediaType,
                          )
                        : AppVideoPersonVideosPage.actor(
                            name: name,
                            mediaType: resolvedMediaType,
                          ),
                  );
                  return;
                }
                if (!Get.isRegistered<VideoMainController>()) return;
                final main = Get.find<VideoMainController>();
                final kind = isDirector
                    ? VideoFilterOverlayKind.director
                    : VideoFilterOverlayKind.actor;
                main.openFilterOverlay(
                  kind: kind,
                  value: name,
                  mediaType: resolvedMediaType,
                );
              }

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: openOverlay,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 120,
                            height: 160,
                            child: url.isNotEmpty
                                ? _SafePersonImage(
                                    url: url,
                                    name: name,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty
                                            ? name.characters.first
                                            : '?',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }
}

class _SafePersonImage extends StatefulWidget {
  final String url;
  final String name;
  final BoxFit fit;

  const _SafePersonImage({
    required this.url,
    required this.name,
    required this.fit,
  });

  @override
  State<_SafePersonImage> createState() => _SafePersonImageState();
}

class _SafePersonImageState extends State<_SafePersonImage> {
  Future<Uint8List?>? _future;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _maybeInitFuture();
  }

  @override
  void didUpdateWidget(covariant _SafePersonImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _maybeInitFuture();
    }
  }

  void _maybeInitFuture() {
    final url = widget.url.trim();
    if (url.isEmpty) {
      _future = null;
      _key = '';
      return;
    }
    if (_key == url && _future != null) return;
    _key = url;
    _future = _fetchAndValidateImageBytes(url);
  }

  bool _looksLikeImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes >= 8) {
      final b = bytes;
      final isPng =
          b[0] == 0x89 &&
          b[1] == 0x50 &&
          b[2] == 0x4E &&
          b[3] == 0x47 &&
          b[4] == 0x0D &&
          b[5] == 0x0A &&
          b[6] == 0x1A &&
          b[7] == 0x0A;
      if (isPng) return true;
    }
    if (bytes.lengthInBytes >= 3) {
      final b = bytes;
      final isJpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
      if (isJpeg) return true;
    }
    if (bytes.lengthInBytes >= 6) {
      final b = bytes;
      final isGif =
          b[0] == 0x47 &&
          b[1] == 0x49 &&
          b[2] == 0x46 &&
          b[3] == 0x38 &&
          (b[4] == 0x37 || b[4] == 0x39) &&
          b[5] == 0x61;
      if (isGif) return true;
    }
    if (bytes.lengthInBytes >= 12) {
      final b = bytes;
      final isRiff =
          b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46;
      final isWebp =
          b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50;
      if (isRiff && isWebp) return true;
    }
    return false;
  }

  Map<String, String> _getHeaders() {
    final headers = <String, String>{};
    try {
      final token = ApiController.instance.accessToken;
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  Future<Uint8List?> _fetchAndValidateImageBytes(String url) async {
    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return null;
    }

    http.Response resp;
    try {
      resp = await http
          .get(uri, headers: _getHeaders())
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }

    final contentType = (resp.headers['content-type'] ?? '').toLowerCase();
    if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
      return null;
    }

    final bytes = resp.bodyBytes;
    if (bytes.isEmpty) return null;
    if (!_looksLikeImageBytes(bytes)) return null;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return _PersonImageError(name: widget.name);
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return _PersonImageError(name: widget.name);
          },
        );
      },
    );
  }
}

class _PersonImageError extends StatelessWidget {
  final String name;

  const _PersonImageError({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.person,
        size: 56,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        semanticLabel: name.isEmpty ? null : name,
      ),
    );
  }
}
