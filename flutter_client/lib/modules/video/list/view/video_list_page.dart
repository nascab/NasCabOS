import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_letter_filter.dart';
import '../controller/video_list_controller.dart';
import 'parts/video_list_grid.dart';
import 'parts/video_list_top_bar.dart';

class VideoListPage extends StatefulWidget {
  final String initialMediaType;
  final String listType;
  final int? albumId;
  final int? collectionId;
  final int? smartAlbumId;
  final bool showTopSpacer;
  final List<String> initialGenres;
  final List<String> initialRegions;
  final List<String> initialActors;
  final List<String> initialDirectors;
  const VideoListPage({
    super.key,
    required this.initialMediaType,
    this.listType = '',
    this.albumId,
    this.collectionId,
    this.smartAlbumId,
    this.showTopSpacer = true,
    this.initialGenres = const <String>[],
    this.initialRegions = const <String>[],
    this.initialActors = const <String>[],
    this.initialDirectors = const <String>[],
  });

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'video_list_${widget.initialMediaType}_${widget.listType}_${widget.albumId ?? 0}_${widget.collectionId ?? 0}_${widget.smartAlbumId ?? 0}_${widget.initialGenres.join('|')}_${widget.initialRegions.join('|')}_${widget.initialActors.join('|')}_${widget.initialDirectors.join('|')}_${UniqueKey()}';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ctrl = Get.isRegistered<VideoListController>(tag: _controllerTag)
        ? Get.find<VideoListController>(tag: _controllerTag)
        : null;
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      // 临近底部自动加载下一页；失败时会切换为手动“加载更多”
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoListController>(
      tag: _controllerTag,
      init: VideoListController(
        initialMediaType: widget.initialMediaType,
        listType: widget.listType,
        albumId: widget.albumId,
        collectionId: widget.collectionId,
        smartAlbumId: widget.smartAlbumId,
        initialGenres: widget.initialGenres,
        initialRegions: widget.initialRegions,
        initialActors: widget.initialActors,
        initialDirectors: widget.initialDirectors,
      ),
      builder: (ctrl) {
        return Column(
          children: [
            if (widget.showTopSpacer) VideoListTopBar(controller: ctrl),
            Expanded(
              child: Obx(() {
                if (ctrl.loading.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rawSearch = ctrl.searchText.value.trim();
                final selectedLetter =
                    rawSearch.length == 1 &&
                        (rawSearch == '#' ||
                            RegExp(r'^[a-zA-Z]$').hasMatch(rawSearch))
                    ? rawSearch.toUpperCase()
                    : null;

                final letterFilter = Positioned.fill(
                  bottom: 10,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: CustomLetterFilter(
                        value: selectedLetter,
                        onChanged: (v) => ctrl.setSearchImmediate(v ?? ''),
                      ),
                    ),
                  ),
                );

                if (ctrl.items.isEmpty) {
                  return Stack(
                    children: [
                      CustomNoData(text: 'no_data'.tr),
                      letterFilter,
                    ],
                  );
                }

                return Stack(
                  children: [
                    Scrollbar(
                      thumbVisibility: true,
                      controller: _scrollController,
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 38, 16),
                            sliver: VideoListGrid(controller: ctrl),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: VideoListFooter(controller: ctrl),
                            ),
                          ),
                        ],
                      ),
                    ),
                    letterFilter,
                  ],
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
