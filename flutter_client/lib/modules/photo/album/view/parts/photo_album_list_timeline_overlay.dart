part of '../photo_album_list_view.dart';

class _AlbumTimelineOverlay extends StatelessWidget {
  final PhotoAlbumItem album;
  final VoidCallback onClose;

  const _AlbumTimelineOverlay({required this.album, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();

    return Positioned.fill(
      child: Material(
        color: customColors?.mainContentBgColor,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Get.theme.dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'back'.tr,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        "${'photo_menu_album_normal'.tr}-${album.name}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PcPhotoTimelineView(
                  key: ValueKey('album_timeline_${album.id}'),
                  listType: 'timeline',
                  albumId: album.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
