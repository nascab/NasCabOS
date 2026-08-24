import 'package:NasCabOS/modules/video/base/views/app_video_list_scaffold.dart';
import 'package:NasCabOS/modules/video/list/controller/video_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoPersonVideosPage extends StatelessWidget {
  final String name;
  final String mediaType;
  final bool isDirector;

  const AppVideoPersonVideosPage.actor({
    super.key,
    required this.name,
    this.mediaType = '',
  }) : isDirector = false;

  const AppVideoPersonVideosPage.director({
    super.key,
    required this.name,
    this.mediaType = '',
  }) : isDirector = true;

  @override
  Widget build(BuildContext context) {
    final prefix = isDirector
        ? 'video_detail_directors'.tr
        : 'video_detail_actors'.tr;
    final title = '$prefix-$name';
    return AppVideoListScaffold(
      title: title,
      controllerTagSeed:
          'person_${isDirector ? 'director' : 'actor'}_${mediaType}_$name',
      controllerBuilder: () {
        return VideoListController(
          initialMediaType: mediaType,
          listType: '',
          initialActors: isDirector ? const <String>[] : <String>[name],
          initialDirectors: isDirector ? <String>[name] : const <String>[],
        );
      },
    );
  }
}
