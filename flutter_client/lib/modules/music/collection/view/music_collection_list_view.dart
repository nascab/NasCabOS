import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_no_data.dart';
import '../../sub_list/view/music_sub_list_overlay.dart';
import '../../../../utils/device_utils.dart';
import '../controller/music_collection_controller.dart';
import 'parts/music_collection_card.dart';
import 'parts/music_collection_dialogs.dart';
import 'parts/music_collection_top_bar.dart';

class MusicCollectionListView extends StatelessWidget {
  const MusicCollectionListView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'music_collection';
    final isPhone = DeviceUtils.isPhone(context);
    return GetBuilder<MusicCollectionController>(
      init: MusicCollectionController(),
      tag: tag,
      dispose: (_) => Get.delete<MusicCollectionController>(tag: tag),
      builder: (ctrl) {
        final theme = Theme.of(context);
        final customColors = theme.extension<CustomColors>();
        final barColor =
            customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
        final list = Column(
          children: [
            isPhone
                ? ColoredBox(
                    color: barColor,
                    child: SafeArea(
                      bottom: false,
                      child: AppMusicCollectionTopBar(controller: ctrl),
                    ),
                  )
                : MusicCollectionTopBar(controller: ctrl),
            Expanded(
              child: SafeArea(
                top: false,
                child: Obx(() {
                  if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ctrl.items.isEmpty) {
                    return CustomNoData(text: 'no_data'.tr);
                  }
                  return CustomScrollView(
                    controller: ctrl.scrollController,
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
                                final collection = ctrl.items[index];
                                return MusicCollectionCard(
                                  collection: collection,
                                  onOpen: () {
                                    if (DeviceUtils.isMobile ||
                                        DeviceUtils.isPhone(context)) {
                                      Get.to(
                                        () => MusicSubListMobilePage(
                                          keyType: 'collection',
                                          name: collection.name,
                                          collectionId: collection.id,
                                        ),
                                      );
                                      return;
                                    }
                                    ctrl.openCollection(collection);
                                  },
                                  onEdit: () =>
                                      MusicCollectionDialogs.showEditDialog(
                                        context,
                                        controller: ctrl,
                                        collection: collection,
                                      ),
                                  onDelete: () =>
                                      MusicCollectionDialogs.confirmDelete(
                                        context,
                                        controller: ctrl,
                                        collection: collection,
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
                          child: SizedBox(
                            width: double.infinity,
                            child: Center(
                              child: ctrl.isLoading.value
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : (!ctrl.hasMore.value
                                        ? Text(
                                            'no_more'.tr,
                                            style: Get.textTheme.bodySmall,
                                          )
                                        : OutlinedButton(
                                            onPressed: ctrl.loadMore,
                                            child: Text('load_more'.tr),
                                          )),
                            ),
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
        final body = Container(
          decoration: BoxDecoration(color: customColors?.mainContentBgColor),
          child: Stack(
            children: [
              list,
              Obx(() {
                final collection = ctrl.activeCollection.value;
                if (collection == null) return const SizedBox.shrink();
                return MusicSubListOverlay(
                  key: ValueKey('collection_music_list_${collection.id}'),
                  keyType: 'collection',
                  name: "${'music_collection_title'.tr}-${collection.name}",
                  collectionId: collection.id,
                  onClose: ctrl.closeCollection,
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
