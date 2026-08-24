import 'dart:async';

import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_item_utils.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:NasCabOS/modules/video/base/views/app_video_item_poster.dart';
import 'package:NasCabOS/modules/video/list/controller/video_list_controller.dart';
import 'package:NasCabOS/modules/video/list/view/app_video_list_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/app_video_home_page_controller.dart';

class AppVideoHomePage extends StatefulWidget {
  final VoidCallback? onOpenMovie;
  final VoidCallback? onOpenTv;
  final VoidCallback? onOpenHistory;

  const AppVideoHomePage({
    super.key,
    this.onOpenMovie,
    this.onOpenTv,
    this.onOpenHistory,
  });

  @override
  State<AppVideoHomePage> createState() => _AppVideoHomePageState();
}

class _AppVideoHomePageState extends State<AppVideoHomePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AppVideoHomePageController>(
      init: AppVideoHomePageController(alertWhenNoSourcePath: true),
      builder: (ctrl) {
        void handleDeleted(VideoHomeItemBean deleted) {
          ctrl.recommend.removeWhere((e) => e.id == deleted.id);
          ctrl.recentPlay.removeWhere((e) => e.id == deleted.id);
          ctrl.recentAddMovie.removeWhere((e) => e.id == deleted.id);
          ctrl.recentAddTv.removeWhere((e) => e.id == deleted.id);
        }

        void handleFavoriteChanged(int indexId, bool isFav) {
          void updateList(RxList<VideoHomeItemBean> list) {
            final i = list.indexWhere((e) => e.id == indexId);
            if (i == -1) return;
            list[i] = list[i].copyWith(isFavorite: isFav);
          }

          updateList(ctrl.recommend);
          updateList(ctrl.recentPlay);
          updateList(ctrl.recentAddMovie);
          updateList(ctrl.recentAddTv);
        }

        return Obx(() {
          final mq = MediaQuery.of(context);
          final padBottom = mq.padding.bottom;
          final topContentInset = mq.padding.top + 48;
          final noData =
              ctrl.recommend.isEmpty &&
              ctrl.recentPlay.isEmpty &&
              ctrl.recentAddMovie.isEmpty &&
              ctrl.recentAddTv.isEmpty;

          return RefreshIndicator(
            onRefresh: () => ctrl.refreshAll(showLoading: false),
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.only(bottom: padBottom + 70),
              children: [
                if (ctrl.recommend.isNotEmpty)
                  _AppVideoRecommendSwiper(items: ctrl.recommend.toList())
                else if (!noData)
                  SizedBox(height: mq.padding.top + 38),
                if (noData && ctrl.loading.value)
                  Padding(
                    padding: EdgeInsets.only(top: topContentInset),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                if (ctrl.recentPlay.isNotEmpty)
                  _AppVideoHorizontalSection(
                    title: 'video_home_recent_play'.tr,
                    items: ctrl.recentPlay.toList(),
                    showProgress: true,
                    onDeleted: handleDeleted,
                    onTapTitle: () {
                      final cb = widget.onOpenHistory;
                      if (cb != null) {
                        cb();
                        return;
                      }
                      Get.to(
                        () => const AppVideoListPage(
                          initialMediaType: '',
                          listType: 'history',
                        ),
                      );
                    },
                    onFavoriteChanged: (item, isFav) =>
                        handleFavoriteChanged(item.id, isFav),
                  ),
                if (ctrl.recentAddMovie.isNotEmpty)
                  _AppVideoHorizontalSection(
                    title: 'video_home_recent_add_movie'.tr,
                    items: ctrl.recentAddMovie.toList(),
                    onDeleted: handleDeleted,
                    onTapTitle: () {
                      final cb = widget.onOpenMovie;
                      if (cb != null) {
                        cb();
                        return;
                      }
                      Get.to(
                        () => const AppVideoListPage(initialMediaType: 'movie'),
                      );
                    },
                    onFavoriteChanged: (item, isFav) =>
                        handleFavoriteChanged(item.id, isFav),
                  ),
                if (ctrl.recentAddTv.isNotEmpty)
                  _AppVideoHorizontalSection(
                    title: 'video_home_recent_add_tv'.tr,
                    items: ctrl.recentAddTv.toList(),
                    onDeleted: handleDeleted,
                    onTapTitle: () {
                      final cb = widget.onOpenTv;
                      if (cb != null) {
                        cb();
                        return;
                      }
                      Get.to(
                        () => const AppVideoListPage(initialMediaType: 'tv'),
                      );
                    },
                    onFavoriteChanged: (item, isFav) =>
                        handleFavoriteChanged(item.id, isFav),
                  ),
                if (noData && !ctrl.loading.value)
                  Padding(
                    padding: EdgeInsets.only(top: topContentInset),
                    child: Center(child: CustomNoData(text: 'no_data'.tr)),
                  ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _AppVideoHorizontalSection extends StatelessWidget {
  final String title;
  final List<VideoHomeItemBean> items;
  final bool showProgress;
  final ValueChanged<VideoHomeItemBean>? onDeleted;
  final VoidCallback? onTapTitle;
  final void Function(VideoHomeItemBean item, bool isFav)? onFavoriteChanged;

  const _AppVideoHorizontalSection({
    required this.title,
    required this.items,
    this.showProgress = false,
    this.onDeleted,
    this.onTapTitle,
    this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    VideoListController.ensureSharedPosterScaleLoaded();
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    const padding = 16.0;
    const spacing = 10.0;
    final baseItemWidth = (width - padding * 2 - spacing * 2) / 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTapTitle,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Obx(() {
          final posterScale = VideoListController.sharedPosterScale.value;
          final itemWidth = baseItemWidth * posterScale;
          return SizedBox(
            height: itemWidth * (3 / 2) + 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, index) {
                final item = items[index];
                final p = showProgress ? item.progress : null;
                return AppVideoItemPoster(
                  item: item,
                  width: itemWidth,
                  progress: p,
                  onDeleted: onDeleted,
                  onFavoriteChanged: (isFav) =>
                      onFavoriteChanged?.call(item, isFav),
                );
              },
              separatorBuilder: (context, index) =>
                  const SizedBox(width: spacing),
              itemCount: items.length,
            ),
          );
        }),
      ],
    );
  }
}

class _AppVideoRecommendSwiper extends StatefulWidget {
  final List<VideoHomeItemBean> items;

  const _AppVideoRecommendSwiper({required this.items});

  @override
  State<_AppVideoRecommendSwiper> createState() =>
      _AppVideoRecommendSwiperState();
}

class _AppVideoRecommendSwiperState extends State<_AppVideoRecommendSwiper> {
  late final PageController _pageController;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _AppVideoRecommendSwiper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _index = 0;
      _pageController.jumpToPage(0);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final next = (_index + 1) % widget.items.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _pill({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.1,
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    final height = MediaQuery.of(context).size.height * 0.52;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _startTimer();
            },
            itemBuilder: (context, i) {
              final item = widget.items[i];
              final imageUrl = VideoUtils.getFanartUrl(item, size: 1000);
              final title = item.nfoName.isNotEmpty
                  ? item.nfoName
                  : item.filename;
              final sub = item.nfoYear > 0 ? item.nfoYear.toString() : '';
              final meta = buildVideoHomeMeta(item);
              final rating = item.nfoScore;
              final typeText = videoMediaTypeText(item.mediaType);
              return GestureDetector(
                onTap: () => AppRoutes.toVideoDetail(item.id),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      CustomExtendedImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        borderRadius: 0,
                        showLoading: false,
                      )
                    else
                      ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.86),
                              Colors.black.withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'video_home_recommend'.tr,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (rating > 0) ...[
                                const SizedBox(width: 10),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: const Color.fromARGB(
                                      255,
                                      229,
                                      181,
                                      39,
                                    ).withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (sub.isNotEmpty || meta.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              <String>[
                                sub,
                                meta,
                              ].where((e) => e.isNotEmpty).join(' · '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                          if (typeText.trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (typeText.trim().isNotEmpty)
                                  _pill(
                                    text: typeText,
                                    bg: Colors.black.withValues(alpha: 0.45),
                                    fg: Colors.white.withValues(alpha: 0.95),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: topPadding + 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.items.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 14 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
