import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/file_util.dart';
import '../../../base/components/custom_hover_select_menu.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_outlined_button.dart';
import '../../timeline/models/photo_timeline_model.dart';
import '../controller/ai_similar_controller.dart';
import '../models/ai_similar_models.dart';

class AiSimilarView extends StatelessWidget {
  const AiSimilarView({super.key});

  @override
  Widget build(BuildContext context) {
    const tag = 'photo_ai_similar';
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<AiSimilarController>(
      init: AiSimilarController(),
      tag: tag,
      dispose: (_) => Get.delete<AiSimilarController>(tag: tag),
      builder: (ctrl) {
        if (DeviceUtils.isMobile) {
          final isAdmin = CurrentUserController.instance.isAdmin;
          const pageSizeOptions = [10, 20, 50, 100];
          return Scaffold(
            backgroundColor: customColors?.mainContentBgColor,
            appBar: AppBar(
              title: Text('photo_menu_ai_similar'.tr),
              actions: [
                Obx(() {
                  final v = ctrl.pageSize.value;
                  final shown = pageSizeOptions.contains(v) ? v : 20;
                  return PopupMenuButton<int>(
                    initialValue: shown,
                    onSelected: ctrl.setPageSize,
                    itemBuilder: (_) => pageSizeOptions
                        .map(
                          (e) => PopupMenuItem<int>(
                            value: e,
                            child: Text(
                              'per_page_groups'.trParams({
                                'count': e.toString(),
                              }),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    icon: const Icon(Icons.view_list_outlined),
                  );
                }),
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    tooltip: 'reset'.tr,
                    onPressed: () async {
                      DialogUtil.showConfirmDialog(
                        title: 'need_confirm'.tr,
                        content: 'photo_ai_similar_reset_confirm'.tr,
                        onConfirm: () async {
                          try {
                            DialogUtil.showLoading(message: 'loading'.tr);
                            final ok = await ctrl.resetSimilarScan();
                            if (!ok) {
                              return;
                            }
                            ToastUtil.show('operation_success'.tr);
                            await ctrl.refreshGroups(showLoading: false);
                          } finally {
                            DialogUtil.dismissLoading();
                          }
                        },
                        confirmText: 'ok'.tr,
                        cancelText: 'cancel'.tr,
                      );
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'refresh'.tr,
                  onPressed: () => ctrl.refreshGroups(showLoading: false),
                ),
              ],
            ),
            body: Stack(
              children: [
                _AiSimilarList(controller: ctrl),
                Obx(() {
                  if (ctrl.selectedPhotoIds.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: _AiSimilarSelectionBar(controller: ctrl),
                  );
                }),
              ],
            ),
          );
        }
        return Container(
          color: customColors?.mainContentBgColor,
          child: Column(
            children: [
              _AiSimilarTopBar(controller: ctrl),
              Expanded(child: _AiSimilarList(controller: ctrl)),
              Obx(() {
                if (ctrl.selectedPhotoIds.isEmpty) {
                  return const SizedBox.shrink();
                }
                return _AiSimilarSelectionBar(controller: ctrl);
              }),
            ],
          ),
        );
      },
    );
  }
}

class _AiSimilarTopBar extends StatelessWidget {
  final AiSimilarController controller;
  const _AiSimilarTopBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    const pageSizeOptions = [10, 20, 50, 100];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dropdown = Obx(() {
            final v = controller.pageSize.value;
            final shown = pageSizeOptions.contains(v) ? v : 20;
            return CustomHoverSelectMenu<int>(
              value: shown,
              height: 44,
              buttonIcon: Icons.view_list_outlined,
              items: pageSizeOptions
                  .map(
                    (e) => CustomHoverSelectMenuItem<int>(
                      value: e,
                      label: 'per_page_groups'.trParams({
                        'count': e.toString(),
                      }),
                      icon: Icons.view_list,
                    ),
                  )
                  .toList(),
              onSelected: controller.setPageSize,
            );
          });

          final buttons = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAdmin)
                CustomBorderedIconButton(
                  icon: Icons.clear_all,
                  tooltip: 'reset'.tr,
                  onTap: () async {
                    DialogUtil.showConfirmDialog(
                      title: 'need_confirm'.tr,
                      content: 'photo_ai_similar_reset_confirm'.tr,
                      onConfirm: () async {
                        try {
                          DialogUtil.showLoading(message: 'loading'.tr);
                          final ok = await controller.resetSimilarScan();
                          if (!ok) {
                            return;
                          }
                          ToastUtil.show('operation_success'.tr);
                          await controller.refreshGroups(showLoading: false);
                        } finally {
                          DialogUtil.dismissLoading();
                        }
                      },
                      confirmText: 'ok'.tr,
                      cancelText: 'cancel'.tr,
                    );
                  },
                ),
              const SizedBox(width: 6),
              CustomBorderedIconButton(
                icon: Icons.refresh,
                tooltip: 'refresh'.tr,
                onTap: () => controller.refreshGroups(showLoading: false),
              ),
            ],
          );

          return Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: dropdown),
              ),
              buttons,
            ],
          );
        },
      ),
    );
  }
}

class _AiSimilarList extends StatelessWidget {
  final AiSimilarController controller;
  const _AiSimilarList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value && controller.groups.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (!controller.similarEnabled.value) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'photo_dedup_disabled'.tr,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              if (CurrentUserController.instance.isAdmin)
                SizedBox(
                  width: 160,
                  height: 44,
                  child: CustomOutlinedButton(
                    compact: false,
                    text: 'photo_ai_enable_now'.tr,
                    onPressed: controller.enableSimilarRecognition,
                  ),
                ),
            ],
          ),
        );
      }

      if (controller.groups.isEmpty) {
        if (controller.hasMore.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return CustomNoData(text: 'no_data'.tr);
      }

      final padding = DeviceUtils.isMobile
          ? const EdgeInsets.fromLTRB(16, 14, 16, 72)
          : const EdgeInsets.fromLTRB(16, 4, 16, 12);
      return ListView.builder(
        controller: controller.scrollController,
        padding: padding,
        itemCount: controller.groups.length + 1,
        itemBuilder: (context, index) {
          if (index >= controller.groups.length) {
            if (!controller.hasMore.value && !controller.isLoading.value) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              child: SizedBox(
                width: double.infinity,
                child: Center(
                  child: controller.isLoading.value
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: CustomOutlinedButton(
                            compact: false,
                            text: 'photo_ai_similar_load_more'.tr,
                            onPressed: controller.loadMore,
                          ),
                        ),
                ),
              ),
            );
          }
          final group = controller.groups[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AiSimilarGroupCard(controller: controller, group: group),
          );
        },
      );
    });
  }
}

class _AiSimilarGroupCard extends StatelessWidget {
  final AiSimilarController controller;
  final AiSimilarGroupItem group;

  const _AiSimilarGroupCard({required this.controller, required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      borderRadius: 10,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'photo_ai_similar_group_hint'.tr,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${group.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = (width / 140).floor().clamp(3, 10);
              const crossAxisSpacing = 6.0;
              const mainAxisSpacing = 6.0;
              final itemWidth =
                  (width - crossAxisSpacing * (crossAxisCount - 1)) /
                  crossAxisCount;
              final thumbHeight = itemWidth.clamp(90.0, 160.0);
              const metaHeight = 54.0;
              final itemHeight = thumbHeight + metaHeight;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: group.photos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisSpacing: mainAxisSpacing,
                  mainAxisExtent: itemHeight,
                ),
                itemBuilder: (context, index) {
                  final photo = group.photos[index];
                  return _AiSimilarPhotoTile(
                    controller: controller,
                    group: group,
                    photo: photo,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AiSimilarPhotoTile extends StatefulWidget {
  final AiSimilarController controller;
  final AiSimilarGroupItem group;
  final TimelinePhotoItem photo;

  const _AiSimilarPhotoTile({
    required this.controller,
    required this.group,
    required this.photo,
  });

  @override
  State<_AiSimilarPhotoTile> createState() => _AiSimilarPhotoTileState();
}

class _AiSimilarPhotoTileState extends State<_AiSimilarPhotoTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiController.instance.getTinyUrl(widget.photo.fullpath);
    return Obx(() {
      final selected = widget.controller.selectedPhotoIds.contains(
        widget.photo.id,
      );
      final sizeBytes =
          widget.controller.photoSizeById[widget.photo.id] ?? widget.photo.size;
      final isMobile = DeviceUtils.isMobile;

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => widget.controller.openGroupPreview(
                  group: widget.group,
                  clicked: widget.photo,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomExtendedImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: 6,
                    ),
                    if (_hover)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    if (selected)
                      Container(
                        decoration: BoxDecoration(
                          color: Get.theme.primaryColor.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Get.theme.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 28,
                          onPressed: () {
                            widget.controller.togglePhotoSelection(
                              widget.photo.id,
                            );
                          },
                          icon: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              FileUtil.formatSize(sizeBytes),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isMobile)
              InkWell(
                onTap: () {
                  DialogUtil.showInfoDialog(
                    title: 'path'.tr,
                    content: widget.photo.fullpath,
                  );
                },
                child: Text(
                  widget.photo.fullpath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              )
            else
              Tooltip(
                message: widget.photo.fullpath,
                waitDuration: const Duration(milliseconds: 300),
                child: Text(
                  widget.photo.fullpath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _AiSimilarSelectionBar extends StatelessWidget {
  final AiSimilarController controller;
  const _AiSimilarSelectionBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final photoCount = controller.selectedPhotoIds.length;
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Text(
              'selected_photos_only'.trParams({'count': photoCount.toString()}),
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: controller.clearSelection,
              child: Text('cancel'.tr),
            ),
            const SizedBox(width: 8),
            if (photoCount > 0)
              ElevatedButton(
                onPressed: controller.trashSelectedPhotos,
                child: Text('put_in_photo_trash'.tr),
              ),
          ],
        ),
      );
    });
  }
}
