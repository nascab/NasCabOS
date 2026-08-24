import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_icon_button.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../../utils/dialog_util.dart';
import '../../base/views/video_item_poster.dart';
import '../../list/controller/video_list_controller.dart';
import '../controller/video_history_controller.dart';

class VideoHistoryPage extends StatefulWidget {
  const VideoHistoryPage({super.key});

  @override
  State<VideoHistoryPage> createState() => _VideoHistoryPageState();
}

class _VideoHistoryPageState extends State<VideoHistoryPage> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;

  @override
  void initState() {
    super.initState();
    _controllerTag = 'video_history_${UniqueKey()}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    VideoListController.ensureSharedPosterScaleLoaded();
    return GetBuilder<VideoHistoryController>(
      tag: _controllerTag,
      init: VideoHistoryController(),
      builder: (ctrl) {
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Obx(() {
                    if (ctrl.loading.value && ctrl.items.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (ctrl.items.isEmpty) {
                      return CustomNoData(text: 'video_history_empty'.tr);
                    }

                    return Scrollbar(
                      thumbVisibility: true,
                      controller: _scrollController,
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            sliver: Obx(() {
                              final posterScale =
                                  VideoListController.sharedPosterScale.value;
                              return SliverLayoutBuilder(
                                builder: (context, constraints) {
                                  final maxWidth = constraints.crossAxisExtent;
                                  final baseWidth = maxWidth < 520
                                      ? 150.0
                                      : 176.0;
                                  final desiredWidth = baseWidth * posterScale;
                                  final crossAxisCount =
                                      (maxWidth / desiredWidth).floor().clamp(
                                        2,
                                        10,
                                      );
                                  final spacing = maxWidth < 520 ? 12.0 : 15.0;
                                  final totalSpacing =
                                      spacing * (crossAxisCount - 1);
                                  final itemWidth =
                                      ((maxWidth - totalSpacing) /
                                              crossAxisCount)
                                          .floorToDouble();
                                  final estimatedHeight = itemWidth * 1.5 + 60;
                                  final aspectRatio =
                                      itemWidth / estimatedHeight;

                                  return SliverGrid(
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      idx,
                                    ) {
                                      final item = ctrl.items[idx];
                                      return VideoItemPoster(
                                        contentPadding: EdgeInsets.zero,
                                        item: item,
                                        width: itemWidth,
                                        progress: item.progress,
                                        onDeleted: (deleted) =>
                                            ctrl.items.removeWhere(
                                              (e) => e.id == deleted.id,
                                            ),
                                      );
                                    }, childCount: ctrl.items.length),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisSpacing: spacing,
                                          crossAxisSpacing: spacing,
                                          childAspectRatio: aspectRatio,
                                        ),
                                  );
                                },
                              );
                            }),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 64)),
                        ],
                      ),
                    );
                  }),
                  Obx(() {
                    if (ctrl.items.isEmpty) return const SizedBox.shrink();
                    return Positioned(
                      right: 20,
                      bottom: 20,
                      child: CustomIconButton(
                        icon: Icons.delete_sweep,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                        ),
                        tooltip: 'video_history_clear'.tr,
                        onPressed: () async {
                          if (ctrl.loading.value) return;
                          final confirmed = await DialogUtil.showConfirmDialog(
                            title: 'need_confirm'.tr,
                            content: 'video_history_clear_confirm'.tr,
                            confirmText: 'ok'.tr,
                            cancelText: 'cancel'.tr,
                          );
                          if (confirmed == true) {
                            await ctrl.clearAll(showLoading: true);
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
