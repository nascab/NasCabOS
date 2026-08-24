import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/photo_timeline_controller.dart';
import 'parts/photo_timeline_control_bar.dart';
import 'parts/photo_timeline_list.dart';
import 'parts/photo_timeline_sidebar.dart';
import 'parts/photo_timeline_hover_date.dart';
import 'parts/photo_timeline_multiselect_bar.dart';

class PcPhotoTimelineView extends GetView<PhotoTimelineController> {
  final String listType;
  final int? albumId;
  final int? collectionId;
  final int? smartAlbumId;
  final int? faceId;
  final String? placeName;
  final bool loadTheDay;
  final String? geohash;

  /// 见 [PhotoTimelineController.alertWhenNoSourcePath]。
  final bool alertWhenNoSourcePath;

  const PcPhotoTimelineView({
    super.key,
    this.listType = 'timeline',
    this.albumId,
    this.collectionId,
    this.smartAlbumId,
    this.faceId,
    this.placeName,
    this.loadTheDay = false,
    this.geohash,
    this.alertWhenNoSourcePath = false,
  });

  @override
  String? get tag {
    final base = loadTheDay ? '${listType}_the_day' : listType;
    var t = base;
    if (albumId != null) t = '${t}_album_$albumId';
    if (collectionId != null) t = '${t}_collection_$collectionId';
    if (smartAlbumId != null) t = '${t}_smart_album_$smartAlbumId';
    if (faceId != null) t = '${t}_face_$faceId';
    if (placeName != null && placeName!.trim().isNotEmpty) {
      t = '${t}_place_name_${placeName!.trim()}';
    }
    if (geohash != null && geohash!.trim().isNotEmpty) {
      t = '${t}_geo_${geohash!.trim()}';
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final controllerTag = tag;
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<PhotoTimelineController>(
      init: PhotoTimelineController(
        initialListType: listType,
        initialAlbumId: albumId,
        initialCollectionId: collectionId,
        initialSmartAlbumId: smartAlbumId,
        initialFaceId: faceId,
        initialPlaceName: placeName,
        initialLoadTheDay: loadTheDay,
        initialGeohash: geohash,
        alertWhenNoSourcePath: alertWhenNoSourcePath,
      ),
      tag: controllerTag,
      dispose: (_) {
        Get.delete<PhotoTimelineController>(tag: controllerTag);
      },
      builder: (_) {
        return Scaffold(
          backgroundColor: customColors?.mainContentBgColor,
          body: Column(
            children: [
              PhotoTimelineControlBar(controllerTag: controllerTag),
              Expanded(
                child: Stack(
                  children: [
                    PhotoTimelineList(controllerTag: controllerTag),
                    PhotoTimelineHoverDateOverlay(controllerTag: controllerTag),
                    PhotoTimelineSidebar(controllerTag: controllerTag),
                    PhotoTimelineMultiSelectBottomBar(
                      controllerTag: controllerTag,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
