import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../base/views/app_base_page.dart';
import 'app_media_tool_items.dart';
import 'image_compress/view/image_compress_view.dart';
import 'image_compress_batch/view/img_batch_compress_view.dart';
import 'media_arrange/view/media_arrange_view.dart';
import 'video_trans/view/video_trans_view.dart';
import 'audio_trans/view/audio_trans_view.dart';

class AppMediaToolSubPage extends StatelessWidget {
  final String pageKey;
  const AppMediaToolSubPage({super.key, required this.pageKey});

  @override
  Widget build(BuildContext context) {
    AppMediaToolItem? item;
    for (final e in appMediaToolItems) {
      if (e.key == pageKey) {
        item = e;
        break;
      }
    }
    final title = item == null ? 'app_media_tool'.tr : item.titleKey.tr;

    final useInternalScaffold = pageKey != 'image.compress';
    if (useInternalScaffold) {
      return _buildBody();
    }

    return AppBasePage(
      title: title,
      body: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(12), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (pageKey == 'image.compress') {
      return const ImageCompressView(appMode: true);
    }
    if (pageKey == 'image.batch_compress') {
      return const ImgBatchCompressView(appMode: true);
    }
    if (pageKey == 'video.trans') {
      return const VideoTransView(appMode: true);
    }
    if (pageKey == 'audio.trans') {
      return const AudioTransView(appMode: true);
    }
    if (pageKey == 'other.media_arrange') {
      return const MediaArrangeView(appMode: true);
    }
    return Center(child: Text('not_implemented_yet'.tr));
  }
}
