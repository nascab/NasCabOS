import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../base/beans/video_item_bean.dart';
import '../../video_main/controller/video_main_controller.dart';
import '../../list/view/video_list_page.dart';
import '../controller/video_home_page_controller.dart';
import 'parts/video_recommend_section.dart';
import 'parts/video_recent_add_section.dart';
import 'parts/video_recent_play_section.dart';

class VideoHomePage extends StatefulWidget {
  const VideoHomePage({super.key});

  @override
  State<VideoHomePage> createState() => _VideoHomePageState();
}

class _VideoHomePageState extends State<VideoHomePage> {
  final ScrollController _scrollController = ScrollController();

  void _openLibrary(String key, {String? fallbackMediaType}) {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().selectPage(key);
      return;
    }
    if (fallbackMediaType != null && fallbackMediaType.trim().isNotEmpty) {
      Get.to(() => VideoListPage(initialMediaType: fallbackMediaType));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoHomePageController>(
      init: VideoHomePageController(alertWhenNoSourcePath: true),
      builder: (ctrl) {
        void handleDeleted(VideoHomeItemBean deleted) {
          ctrl.recommend.removeWhere((e) => e.id == deleted.id);
          ctrl.recentPlay.removeWhere((e) => e.id == deleted.id);
          ctrl.recentAddMovie.removeWhere((e) => e.id == deleted.id);
          ctrl.recentAddTv.removeWhere((e) => e.id == deleted.id);
        }

        return Column(
          children: [
            // _TopBar(onRefresh: () => ctrl.refreshAll(showLoading: true)),
            Expanded(
              child: Obx(() {
                final noData =
                    ctrl.recommend.isEmpty &&
                    ctrl.recentPlay.isEmpty &&
                    ctrl.recentAddMovie.isEmpty &&
                    ctrl.recentAddTv.isEmpty;

                if (noData) {
                  if (ctrl.loading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CustomNoData(text: 'no_data'.tr);
                }

                return Scrollbar(
                  thumbVisibility: true,
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        VideoRecommendSection(
                          items: ctrl.recommend.toList(),
                          onDeleted: handleDeleted,
                        ),
                        VideoRecentPlaySection(
                          items: ctrl.recentPlay.toList(),
                          onTap: () => _openLibrary('library.history'),
                          onDeleted: handleDeleted,
                        ),
                        VideoRecentAddSection(
                          items: ctrl.recentAddMovie.toList(),
                          title: 'video_home_recent_add_movie'.tr,
                          onTap: () => _openLibrary(
                            'library.movie',
                            fallbackMediaType: 'movie',
                          ),
                          onDeleted: handleDeleted,
                        ),
                        VideoRecentAddSection(
                          items: ctrl.recentAddTv.toList(),
                          title: 'video_home_recent_add_tv'.tr,
                          onTap: () => _openLibrary(
                            'library.tv',
                            fallbackMediaType: 'tv',
                          ),
                          onDeleted: handleDeleted,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
