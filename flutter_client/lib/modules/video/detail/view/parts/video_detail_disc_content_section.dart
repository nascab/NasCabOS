import 'package:flutter/material.dart';

import '../../../../../core/api/api_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../controller/video_detail_controller.dart';
import '../../service/video_detail_api_service.dart';

class VideoDetailDiscContentSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailDiscContentSection({super.key, required this.ctrl});

  String _thumbUrl(Map<String, dynamic> item) {
    final internalPath = (item['thumbnail_internal_path']?.toString() ?? '').trim();
    final thumbPath = (item['thumbnail_path']?.toString() ?? '').trim();
    if (thumbPath.isNotEmpty) {
      return ApiController.instance.getTinyUrl(thumbPath);
    }
    if (internalPath.isEmpty) return '';
    return VideoDetailApiService.instance.getDiscContentThumbUrl(
      indexId: ctrl.indexId,
      internalPath: internalPath,
    );
  }

  void _playItem(BuildContext context, int index) {
    final items = ctrl.discContentList;
    if (index < 0 || index >= items.length) return;
    final playlist = ctrl.buildDiscPlaybackPlaylist();
    if (playlist.isEmpty) return;
    final initialIndex = ctrl.findDiscPlaybackIndex(items[index]);
    AppRoutes.toVideoPlayer(
      playlist: playlist,
      initialIndex: initialIndex,
      ignoreFindSub: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ctrl.showDiscContentSection) return const SizedBox.shrink();
    final items = ctrl.discContentList;
    final loading = ctrl.discContentLoading.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '原盘内容',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!loading && items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '暂无原盘内容',
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.75)),
            ),
          ),
        if (items.isNotEmpty)
          Column(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final title = (item['title']?.toString() ?? '').trim();
              final displayName = (item['display_name']?.toString() ?? '').trim();
              final thumbUrl = _thumbUrl(item);
              return Padding(
                padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _playItem(context, index),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: thumbUrl.isNotEmpty
                              ? CustomExtendedImage(
                                  imageUrl: thumbUrl,
                                  width: 128,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  borderRadius: 10,
                                  errorBuilder: (_, _, _) => _thumbPlaceholder(context),
                                )
                              : _thumbPlaceholder(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isNotEmpty ? title : 'Title ${index + 1}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                displayName.isNotEmpty ? displayName : '-',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.play_circle_outline),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _thumbPlaceholder(BuildContext context) {
    return Container(
      width: 128,
      height: 72,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
