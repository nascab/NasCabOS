part of '../photo_collection_list_view.dart';

class _CollectionTimelineOverlay extends StatelessWidget {
  final PhotoCollectionItem collection;
  final VoidCallback onClose;

  const _CollectionTimelineOverlay({
    required this.collection,
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
                        "${'photo_menu_album_collection'.tr}-${collection.name}",
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
                  key: ValueKey('collection_timeline_${collection.id}'),
                  listType: 'timeline',
                  collectionId: collection.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
