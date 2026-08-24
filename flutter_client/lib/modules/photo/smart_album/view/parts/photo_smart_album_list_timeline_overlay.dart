part of '../photo_smart_album_list_view.dart';

class _SmartAlbumTimelineOverlay extends StatelessWidget {
  final PhotoSmartAlbumItem album;
  final VoidCallback onClose;

  const _SmartAlbumTimelineOverlay({
    required this.album,
    required this.onClose,
  });

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
                        "${'photo_menu_album_smart'.tr}-${album.name}",
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
                  key: ValueKey('smart_album_timeline_${album.id}'),
                  listType: 'timeline',
                  smartAlbumId: album.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
