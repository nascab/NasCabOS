import 'package:NasCabOS/modules/video/base/views/app_video_list_scaffold.dart';
import 'package:NasCabOS/modules/video/list/controller/video_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoAlbumVideosPage extends StatelessWidget {
  final String title;
  final int? albumId;
  final int? smartAlbumId;
  final int? collectionId;

  const AppVideoAlbumVideosPage.smartAlbum({
    super.key,
    required int this.smartAlbumId,
    required String name,
  }) : title = name,
       albumId = null,
       collectionId = null;

  const AppVideoAlbumVideosPage.collection({
    super.key,
    required int this.collectionId,
    required String name,
  }) : title = name,
       albumId = null,
       smartAlbumId = null;

  const AppVideoAlbumVideosPage.album({
    super.key,
    required int this.albumId,
    required String name,
  }) : title = name,
       collectionId = null,
       smartAlbumId = null;

  String get _typeSuffix {
    final inAlbum = (albumId ?? 0) > 0;
    final inCollection = (collectionId ?? 0) > 0;
    final inSmartAlbum = (smartAlbumId ?? 0) > 0;
    if (inAlbum) return 'video_custom_album_title'.tr;
    if (inCollection) return 'video_collection_title'.tr;
    return inSmartAlbum ? 'video_smart_album_title'.tr : 'video_menu_albums'.tr;
  }

  String get _navTitle => '$title-$_typeSuffix';

  @override
  Widget build(BuildContext context) {
    return AppVideoListScaffold(
      title: _navTitle,
      controllerTagSeed:
          'album_${albumId ?? 0}_${collectionId ?? 0}_${smartAlbumId ?? 0}'
              .trim(),
      controllerBuilder: () {
        return VideoListController(
          initialMediaType: '',
          listType: '',
          albumId: albumId,
          collectionId: collectionId,
          smartAlbumId: smartAlbumId,
        );
      },
    );
  }
}
