import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/photo_timeline_controller.dart';
import 'app_photo_timeline_view.dart';
import 'parts/app_photo_timeline_multiselect_bar.dart';

enum AppPhotoAlbumTimelineType { album, smartAlbum, collection }

class AppPhotoAlbumTimelinePage extends StatefulWidget {
  final AppPhotoAlbumTimelineType type;
  final int id;
  final String name;

  const AppPhotoAlbumTimelinePage({
    super.key,
    required this.type,
    required this.id,
    required this.name,
  });

  @override
  State<AppPhotoAlbumTimelinePage> createState() =>
      _AppPhotoAlbumTimelinePageState();
}

class _AppPhotoAlbumTimelinePageState extends State<AppPhotoAlbumTimelinePage> {
  late final String _timelineTag;

  @override
  void initState() {
    super.initState();
    _timelineTag = 'app_photo_album_timeline_${UniqueKey()}';

    Get.put(
      PhotoTimelineController(
        initialListType: 'timeline',
        initialAlbumId: widget.type == AppPhotoAlbumTimelineType.album
            ? widget.id
            : null,
        initialCollectionId: widget.type == AppPhotoAlbumTimelineType.collection
            ? widget.id
            : null,
        initialSmartAlbumId: widget.type == AppPhotoAlbumTimelineType.smartAlbum
            ? widget.id
            : null,
      ),
      tag: _timelineTag,
    );
  }

  @override
  void dispose() {
    Get.delete<PhotoTimelineController>(tag: _timelineTag, force: true);
    super.dispose();
  }

  String _typeLabel() {
    if (widget.type == AppPhotoAlbumTimelineType.album) {
      return 'photo_menu_album_normal'.tr;
    }
    if (widget.type == AppPhotoAlbumTimelineType.smartAlbum) {
      return 'photo_menu_album_smart'.tr;
    }
    return 'photo_menu_album_collection'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.name} · ${_typeLabel()}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: AppPhotoTimelineView(
        controllerTag: _timelineTag,
        showSearchAction: true,
      ),
      bottomNavigationBar: AppPhotoTimelineMultiSelectBottomBar(
        controllerTag: _timelineTag,
      ),
    );
  }
}
