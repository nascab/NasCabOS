import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_button.dart';
import '../../../base/components/custom_no_data.dart';
import '../../sub_list/view/music_sub_list_overlay.dart';
import '../../../../utils/device_utils.dart';
import '../controller/play_list_controller.dart';
import 'parts/play_list_dialogs.dart';
import 'parts/play_list_list_card.dart';
import 'parts/play_list_top_bar.dart';

class PlayListListView extends StatelessWidget {
  final bool selectionMode;
  const PlayListListView({super.key, this.selectionMode = false});

  @override
  Widget build(BuildContext context) {
    final isPhone = DeviceUtils.isPhone(context);
    final tag = 'music_play_list_${DateTime.now().microsecondsSinceEpoch}';
    return GetBuilder<PlayListController>(
      init: PlayListController(),
      tag: tag,
      dispose: (_) => Get.delete<PlayListController>(tag: tag),
      builder: (ctrl) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        final barColor =
            customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
        final overlayCtrl = selectionMode
            ? null
            : (Get.isRegistered<PlayListOverlayController>()
                  ? Get.find<PlayListOverlayController>()
                  : Get.put(PlayListOverlayController()));
        final list = Column(
          children: [
            selectionMode
                ? (isPhone
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'back'.tr,
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.close),
                                ),
                                Expanded(
                                  child: Text(
                                    'music_playlist_select'.tr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Get.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : PlayListTopBar(
                          controller: ctrl,
                          selectionMode: selectionMode,
                        ))
                : (isPhone
                      ? ColoredBox(
                          color: barColor,
                          child: SafeArea(
                            bottom: false,
                            child: AppPlayListTopBar(controller: ctrl),
                          ),
                        )
                      : PlayListTopBar(controller: ctrl, selectionMode: false)),
            Expanded(
              child: SafeArea(
                top: false,
                child: Obx(() {
                  if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ctrl.items.isEmpty) {
                    if (selectionMode) {
                      return Center(
                        child: CustomButton(
                          text: 'create'.tr,
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            final item =
                                await PlayListDialogs.showCreateForSelection(
                                  context,
                                  controller: ctrl,
                                );
                            if (item != null && context.mounted) {
                              Navigator.of(context).pop(item);
                            }
                          },
                        ),
                      );
                    }
                    return CustomNoData(text: 'no_data'.tr);
                  }

                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.crossAxisExtent;
                            final isMobile = isPhone && width < 750;
                            return SliverGrid(
                              gridDelegate: isMobile
                                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 1,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 1.8,
                                    )
                                  : const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 380,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 1.8,
                                    ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = ctrl.items[index];
                                return PlayListListCard(
                                  item: item,
                                  selectionMode: selectionMode,
                                  onOpen: selectionMode
                                      ? () => Navigator.of(context).pop(item)
                                      : () {
                                          if (DeviceUtils.isMobile ||
                                              DeviceUtils.isPhone(context)) {
                                            Get.to(
                                              () => MusicSubListMobilePage(
                                                keyType: 'playlist',
                                                name: item.name,
                                                listId: item.id,
                                              ),
                                            );
                                            return;
                                          }
                                          ctrl.openList(item);
                                        },
                                  onRename: () =>
                                      PlayListDialogs.showRenameDialog(
                                        context,
                                        controller: ctrl,
                                        item: item,
                                      ),
                                  onDelete: () => PlayListDialogs.confirmDelete(
                                    context,
                                    controller: ctrl,
                                    item: item,
                                  ),
                                );
                              }, childCount: ctrl.items.length),
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Center(
                            child: Obx(() {
                              if (ctrl.isLoading.value &&
                                  ctrl.items.isNotEmpty) {
                                return const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }
                              if (!ctrl.hasMore.value) {
                                return Text('music_playlist_no_more'.tr);
                              }
                              return OutlinedButton(
                                onPressed: ctrl.loadMore,
                                child: Text('music_playlist_load_more'.tr),
                              );
                            }),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ],
        );

        if (selectionMode) return list;
        final body = Container(
          decoration: BoxDecoration(color: customColors?.mainContentBgColor),
          child: Stack(
            children: [
              list,
              Obx(() {
                final payload = overlayCtrl!.active.value;
                if (payload == null) return const SizedBox.shrink();
                return MusicSubListOverlay(
                  key: ValueKey('playlist_music_list_${payload.listId}'),
                  keyType: 'playlist',
                  name: '${'music_menu_library_playlists'.tr}-${payload.name}',
                  listId: payload.listId,
                  onClose: ctrl.closeList,
                );
              }),
            ],
          ),
        );
        if (!isPhone) return body;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: barColor,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness,
            systemNavigationBarColor: barColor,
            systemNavigationBarIconBrightness:
                theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarDividerColor: barColor,
          ),
          child: body,
        );
      },
    );
  }
}
