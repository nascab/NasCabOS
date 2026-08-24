import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/custom_colors.dart';
import '../../../../modules/base/components/custom_no_data.dart';
import '../../../../modules/base/components/custom_bordered_icon_button.dart';
import '../../../../modules/base/components/custom_expandable_search_bar.dart';
import '../controller/photo_trash_controller.dart';
import 'parts/photo_trash_item.dart';

/// 手机端回收站页面
class AppPhotoTrashPage extends StatelessWidget {
  const AppPhotoTrashPage({super.key});

  static const String _controllerTag = 'app_photo_trash';

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PhotoTrashController>(
      init: PhotoTrashController(),
      tag: _controllerTag,
      dispose: (_) => Get.delete<PhotoTrashController>(tag: _controllerTag),
      builder: (controller) {
        return Scaffold(
          backgroundColor:
              Theme.of(context).extension<CustomColors>()?.mainContentBgColor ??
              Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(title: Text('recycle_bin'.tr)),
          body: _AppPhotoTrashBody(controller: controller),
          bottomNavigationBar: Obx(() {
            if (controller.photoItems.isEmpty) {
              return const SizedBox.shrink();
            }
            return _AppPhotoTrashBottomBar(controller: controller);
          }),
        );
      },
    );
  }
}

class _AppPhotoTrashBody extends StatelessWidget {
  final PhotoTrashController controller;

  const _AppPhotoTrashBody({required this.controller});

  static const double _horizontalPadding = 6;
  static const double _spacing = 2;

  Future<void> _showFilterSheet(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'filter'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Get.back(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Obx(
                () => Column(
                  children: [
                    RadioListTile<String>(
                      value: 'all',
                      groupValue: controller.fileType.value,
                      onChanged: (v) {
                        if (v != null) {
                          controller.changeFileType(v);
                          Get.back();
                        }
                      },
                      title: Text('all'.tr),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'photo',
                      groupValue: controller.fileType.value,
                      onChanged: (v) {
                        if (v != null) {
                          controller.changeFileType(v);
                          Get.back();
                        }
                      },
                      title: Text('timeline_photos'.tr),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'video',
                      groupValue: controller.fileType.value,
                      onChanged: (v) {
                        if (v != null) {
                          controller.changeFileType(v);
                          Get.back();
                        }
                      },
                      title: Text('timeline_videos'.tr),
                      dense: true,
                    ),
                    RadioListTile<String>(
                      value: 'livephoto',
                      groupValue: controller.fileType.value,
                      onChanged: (v) {
                        if (v != null) {
                          controller.changeFileType(v);
                          Get.back();
                        }
                      },
                      title: Text('timeline_live_photos'.tr),
                      dense: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Obx(() {
          if (controller.isMultiSelectMode.value) {
            return const SizedBox.shrink();
          }
          final isDesc = controller.sortOrder.value == 'desc';
          return SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 10),
                CustomBorderedIconButton(
                  icon: isDesc ? Icons.rotate_left : Icons.rotate_right,
                  tooltip: isDesc
                      ? 'photo_timeline_sort_desc'.tr
                      : 'photo_timeline_sort_asc'.tr,
                  onTap: controller.toggleSortOrder,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomExpandableSearchBar(
                    hintText: 'photo_timeline_search_hint'.tr,
                    controller: controller.searchController,
                    onChanged: controller.onSearchChanged,
                    onClear: controller.clearSearch,
                    defaultExpanded: true,
                  ),
                ),
                const SizedBox(width: 8),
                CustomBorderedIconButton(
                  icon: Icons.check_box_outlined,
                  tooltip: 'multi_select'.tr,
                  onTap: controller.toggleMultiSelectMode,
                ),
                const SizedBox(width: 8),
                Obx(() {
                  final active = controller.fileType.value != 'all';
                  return CustomBorderedIconButton(
                    icon: active ? Icons.filter_alt : Icons.filter_alt_outlined,
                    tooltip: 'filter'.tr,
                    active: active,
                    onTap: () => _showFilterSheet(context),
                  );
                }),
                const SizedBox(width: 10),
              ],
            ),
          );
        }),
        Expanded(
          child: Obx(() {
            if (controller.isLoading.value && controller.photoItems.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (controller.photoItems.isEmpty) {
              return CustomNoData(text: 'recycle_bin_empty'.tr);
            }

            final bottomPadding = controller.isMultiSelectMode.value
                ? 76.0
                : 16.0;

            return RefreshIndicator(
              onRefresh: () => controller.refreshList(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = math.max(
                    0.0,
                    constraints.maxWidth - _horizontalPadding * 2,
                  );
                  const cellSize = 100.0;
                  final crossAxisCount = math.max(
                    1,
                    ((contentWidth + _spacing) / (cellSize + _spacing)).floor(),
                  );

                  return GridView.builder(
                    controller: controller.scrollController,
                    padding: EdgeInsets.only(
                      left: _horizontalPadding,
                      right: _horizontalPadding,
                      top: 8,
                      bottom: bottomPadding,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: _spacing,
                      mainAxisSpacing: _spacing,
                      childAspectRatio: 1.0,
                    ),
                    itemCount:
                        controller.photoItems.length +
                        (controller.hasMore.value ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == controller.photoItems.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final photo = controller.photoItems[index];
                      return PhotoTrashItem(
                        controller: controller,
                        photo: photo,
                      );
                    },
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// 手机端回收站底部操作栏：常驻「恢复全部」「清空」；多选时「恢复」「删除」「取消」
class _AppPhotoTrashBottomBar extends StatelessWidget {
  final PhotoTrashController controller;

  const _AppPhotoTrashBottomBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surface;

    return Obx(() {
      if (controller.isMultiSelectMode.value) {
        final disabled = controller.selectedItems.isEmpty;
        return Container(
          color: bgColor,
          child: SafeArea(
            top: false,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  top: BorderSide(color: theme.dividerColor, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'items_selected'.trParams({
                        'count': controller.selectedItems.length.toString(),
                      }),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: disabled ? null : controller.restoreSelected,
                    child: Text('restore'.tr),
                  ),
                  TextButton(
                    onPressed: disabled ? null : controller.deleteSelected,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text('delete'.tr),
                  ),
                  TextButton(
                    onPressed: () {
                      controller.isMultiSelectMode.value = false;
                      controller.selectedItems.clear();
                    },
                    child: Text('cancel'.tr),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Container(
        color: bgColor,
        child: SafeArea(
          top: false,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'total_count'.trParams({
                      'count': controller.photoItems.length.toString(),
                    }),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.restoreAll,
                  child: Text('restore_all'.tr),
                ),
                TextButton(
                  onPressed: controller.emptyTrash,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text('empty_trash'.tr),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
