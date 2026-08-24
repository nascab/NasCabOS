import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../../core/api/api_controller.dart';
import '../../models/album_artist_list_models.dart';

class AlbumArtistItemCard extends StatelessWidget {
  final AlbumArtistGroupItem item;
  final String badgeLabel;
  final double width;
  final double coverSize;
  final VoidCallback onTap;

  const AlbumArtistItemCard({
    super.key,
    required this.item,
    required this.badgeLabel,
    required this.width,
    required this.coverSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleSmall;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final subtitle = '${max(0, item.indexCount)}首';

    return Column(
      children: [
        SizedBox(
          width: coverSize,
          height: coverSize,
          child: CustomAlbum(
            preview: Stack(
              fit: StackFit.expand,
              children: [
                _buildCover(theme),
                if (badgeLabel.trim().isNotEmpty)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: onTap,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 46,
          child: Column(
            children: [
              Tooltip(
                message: item.name,
                waitDuration: const Duration(milliseconds: 300),
                child: SizedBox(
                  width: width,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: titleStyle,
                  ),
                ),
              ),
              if (subtitle.isNotEmpty)
                SizedBox(
                  width: width,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: subtitleStyle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCover(ThemeData theme) {
    final coverFilePath = item.firstFilePath.trim();
    if (coverFilePath.isNotEmpty) {
      final url = ApiController.instance.getMusicCoverUrl(
        filePath: coverFilePath,
        size: 200,
      );
      if (url.isNotEmpty) {
        return CustomExtendedImage(
          imageUrl: url,
          fit: BoxFit.cover,
          showLoading: false,
          borderRadius: 0,
          errorBuilder: (context, error, stackTrace) => _fallbackCover(theme),
        );
      }
    }
    return _fallbackCover(theme);
  }

  Widget _fallbackCover(ThemeData theme) {
    final assetPath = _pickFallbackCoverAsset();
    return Container(
      color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
      child: Image.asset(
        assetPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  String _pickFallbackCoverAsset() {
    final seed = item.name.hashCode;
    final rng = Random(seed);
    final idx = rng.nextInt(20) + 1;
    return 'assets/music/musicCover/other$idx.jpg';
  }
}
