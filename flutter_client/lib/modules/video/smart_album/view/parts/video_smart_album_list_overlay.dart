part of '../video_smart_album_list_view.dart';

class _SmartAlbumOverlay extends StatelessWidget {
  final VideoSmartAlbumItem album;
  final VoidCallback onClose;

  const _SmartAlbumOverlay({required this.album, required this.onClose});

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
                        "${'video_smart_album_title'.tr}-${album.name}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Get.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: VideoListPage(
                  key: ValueKey('video_smart_album_list_${album.id}'),
                  initialMediaType: '',
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
