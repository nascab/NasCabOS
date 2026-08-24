import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_letter_filter.dart';
import '../../../../utils/device_utils.dart';
import '../controller/album_artist_list_controller.dart';
import 'parts/album_artist_list_grid.dart';
import 'parts/album_artist_list_top_bar.dart';
import '../../sub_list/controller/music_sub_list_controller.dart';
import '../../sub_list/view/music_sub_list_overlay.dart';

class AlbumArtistListPage extends StatefulWidget {
  final String keyType;
  final AlbumArtistListSortBy initialSortBy;
  final AlbumArtistListSortOrder initialSortOrder;
  const AlbumArtistListPage({
    super.key,
    required this.keyType,
    this.initialSortBy = AlbumArtistListSortBy.count,
    this.initialSortOrder = AlbumArtistListSortOrder.desc,
  });

  @override
  State<AlbumArtistListPage> createState() => _AlbumArtistListPageState();
}

class _AlbumArtistListPageState extends State<AlbumArtistListPage> {
  final ScrollController _scrollController = ScrollController();
  late final String _controllerTag;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'music_key_list_${widget.keyType}_${widget.initialSortBy}_${widget.initialSortOrder}_${UniqueKey()}';
    if (!Get.isRegistered<AlbumArtistListController>(tag: _controllerTag)) {
      Get.put(
        AlbumArtistListController(
          keyType: widget.keyType,
          initialSortBy: widget.initialSortBy,
          initialSortOrder: widget.initialSortOrder,
        ),
        tag: _controllerTag,
      );
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (Get.isRegistered<AlbumArtistListController>(tag: _controllerTag)) {
      Get.delete<AlbumArtistListController>(tag: _controllerTag);
    }
    if (Get.isRegistered<MusicSubListOverlayController>()) {
      final overlayCtrl = Get.find<MusicSubListOverlayController>();
      overlayCtrl.close();
    }
    super.dispose();
  }

  void _onScroll() {
    final ctrl =
        Get.isRegistered<AlbumArtistListController>(tag: _controllerTag)
        ? Get.find<AlbumArtistListController>(tag: _controllerTag)
        : null;
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AlbumArtistListController>(
      tag: _controllerTag,
      builder: (ctrl) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        final barColor =
            customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
        final overlayCtrl = Get.isRegistered<MusicSubListOverlayController>()
            ? Get.find<MusicSubListOverlayController>()
            : Get.put(MusicSubListOverlayController());

        void openSubList(String name) {
          if (DeviceUtils.isMobile || DeviceUtils.isPhone(context)) {
            Get.to(
              () => MusicSubListMobilePage(keyType: widget.keyType, name: name),
            );
            return;
          }
          overlayCtrl.open(keyType: widget.keyType, name: name);
        }

        final list = Column(
          children: [
            DeviceUtils.isPhone(context)
                ? ColoredBox(
                    color: barColor,
                    child: AppAlbumArtistListTopBar(controller: ctrl),
                  )
                : AlbumArtistListTopBar(controller: ctrl),
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

                final letterFilter = Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: DeviceUtils.isPhone(context)
                        ? const EdgeInsets.only(right: 10)
                        : const EdgeInsets.only(right: 10, bottom: 10),
                    child: CustomLetterFilter(
                      value: selectedLetter,
                      centerWhenBoundedHeight: DeviceUtils.isPhone(context),
                      onChanged: (v) => ctrl.setSearchImmediate(v ?? ''),
                    ),
                  ),
                );

                if (ctrl.items.isEmpty) {
                  return Stack(
                    children: [
                      Center(child: CustomNoData(text: 'no_data'.tr)),
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
                            padding: const EdgeInsets.fromLTRB(16, 0, 28, 66),
                            sliver: AlbumArtistListGrid(
                              controller: ctrl,
                              onOpenSubList: openSubList,
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: AlbumArtistListFooter(controller: ctrl),
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

        return Stack(
          children: [
            list,
            Obx(() {
              final payload = overlayCtrl.active.value;
              if (payload == null) return const SizedBox.shrink();
              return MusicSubListOverlay(
                key: ValueKey(
                  'music_sub_list_${payload.keyType}_${payload.seriesIndexId ?? 0}_${payload.name}',
                ),
                keyType: payload.keyType,
                name: payload.name,
                onClose: overlayCtrl.close,
              );
            }),
          ],
        );
      },
    );
  }
}
