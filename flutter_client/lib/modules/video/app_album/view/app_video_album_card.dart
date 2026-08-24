import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:flutter/material.dart';

class AppVideoAlbumCard extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final IconData? topLeftIcon;
  final VoidCallback? onTopLeftTap;
  final List<String> previewUrls;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const AppVideoAlbumCard({
    super.key,
    required this.title,
    required this.titleIcon,
    this.topLeftIcon,
    this.onTopLeftTap,
    required this.previewUrls,
    required this.onTap,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: _PreviewStrip(urls: previewUrls)),
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 64,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  Icon(titleIcon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: topLeftIcon == null
                  ? const SizedBox.shrink()
                  : Material(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(18),
                      child: onTopLeftTap == null
                          ? Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                topLeftIcon,
                                color: Colors.white,
                                size: 18,
                              ),
                            )
                          : InkWell(
                              onTap: onTopLeftTap,
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  topLeftIcon,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                    ),
            ),
            if (onMore != null)
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: onMore,
                    borderRadius: BorderRadius.circular(18),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.more_horiz,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  final List<String> urls;
  const _PreviewStrip({required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      final theme = Theme.of(context);
      return Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        child: Icon(
          Icons.video_collection_outlined,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          size: 46,
        ),
      );
    }

    Widget image(String url) {
      return CustomExtendedImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
        showLoading: false,
      );
    }

    final children = <Widget>[];
    for (int i = 0; i < urls.length; i++) {
      children.add(Expanded(child: image(urls[i])));
      if (i != urls.length - 1) {
        children.add(const SizedBox(width: 1));
      }
    }
    return Row(children: children);
  }
}
