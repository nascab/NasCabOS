import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../../../core/routes/app_routes.dart';
import '../../../base/components.dart';
import '../../../base/components/custom_switch.dart';
import '../../../files/views/folder_picker_dialog.dart';
import '../../../home/views/pc_home_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../controller/video_trans_controller.dart';

part 'parts/video_trans_helpers.dart';
part 'parts/video_trans_key_value_row.dart';
part 'parts/video_trans_dialog.dart';
part 'parts/video_trans_task_card.dart';

class VideoTransView extends StatelessWidget {
  final bool appMode;
  const VideoTransView({super.key, this.appMode = false});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<VideoTransController>(
      init: VideoTransController(),
      builder: (ctrl) {
        if (appMode) {
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: Text('media_tool_menu_video_trans'.tr),
              actions: [
                IconButton(
                  tooltip: 'media_tool_menu_video_trans_help'.tr,
                  onPressed: () {
                    DialogUtil.showInfoDialog(
                      title: 'media_tool_menu_video_trans'.tr,
                      content: 'media_tool_menu_video_trans_help'.tr,
                    );
                  },
                  icon: const Icon(Icons.help_outline),
                ),
                IconButton(
                  tooltip: 'refresh'.tr,
                  onPressed: () => ctrl.refreshList(showLoading: true),
                  icon: const Icon(Icons.refresh_outlined),
                ),
                IconButton(
                  tooltip: 'create'.tr,
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => _VideoTransDialog(ctrl: ctrl),
                    );
                  },
                  icon: const Icon(Icons.add_outlined),
                ),
              ],
            ),
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Obx(() {
                final loading = ctrl.isLoading.value;
                final err = ctrl.errorText.value.trim();
                final list = ctrl.tasks;
                if (loading && list.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (err.isNotEmpty && list.isEmpty) {
                  return Center(child: Text(err));
                }
                if (list.isEmpty) {
                  return const CustomNoData();
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    return _VideoTransTaskCard(ctrl: ctrl, item: list[idx]);
                  },
                );
              }),
            ),
          );
        }
        final compact = appMode || DeviceUtils.isPhone(context);
        final customColors = Theme.of(context).extension<CustomColors>();
        final edgePadding = compact
            ? EdgeInsets.zero
            : const EdgeInsets.all(12);

        Widget buildHeader() {
          return CustomGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${'media_tool_menu_video'.tr}-${'media_tool_menu_video_trans'.tr}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'media_tool_menu_video_trans_help'.tr,
                                    waitDuration: const Duration(
                                      milliseconds: 300,
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        DialogUtil.showInfoDialog(
                                          title:
                                              'media_tool_menu_video_trans'.tr,
                                          content:
                                              'media_tool_menu_video_trans_help'
                                                  .tr,
                                        );
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.help_outline,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            CustomButton(
                              text: 'refresh'.tr,
                              onPressed: () =>
                                  ctrl.refreshList(showLoading: true),
                              isPrimary: false,
                              icon: const Icon(Icons.refresh_outlined),
                            ),
                            CustomButton(
                              text: 'create'.tr,
                              onPressed: () async {
                                await showDialog<bool>(
                                  context: context,
                                  builder: (_) => _VideoTransDialog(ctrl: ctrl),
                                );
                              },
                              icon: const Icon(Icons.add_outlined),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${'media_tool_menu_video'.tr}-${'media_tool_menu_video_trans'.tr}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'media_tool_menu_video_trans_help'.tr,
                                    waitDuration: const Duration(
                                      milliseconds: 300,
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        DialogUtil.showInfoDialog(
                                          title:
                                              'media_tool_menu_video_trans'.tr,
                                          content:
                                              'media_tool_menu_video_trans_help'
                                                  .tr,
                                        );
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.help_outline,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        CustomButton(
                          text: 'refresh'.tr,
                          onPressed: () => ctrl.refreshList(showLoading: true),
                          isPrimary: false,
                          icon: const Icon(Icons.refresh_outlined),
                        ),
                        const SizedBox(width: 8),
                        CustomButton(
                          text: 'create'.tr,
                          onPressed: () async {
                            await showDialog<bool>(
                              context: context,
                              builder: (_) => _VideoTransDialog(ctrl: ctrl),
                            );
                          },
                          icon: const Icon(Icons.add_outlined),
                        ),
                      ],
                    ),
            ),
          );
        }

        return Container(
          color: customColors?.mainContentBgColor,
          child: Column(
            children: [
              Padding(
                padding: edgePadding.copyWith(bottom: 0),
                child: buildHeader(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  final loading = ctrl.isLoading.value;
                  final err = ctrl.errorText.value.trim();
                  final list = ctrl.tasks;

                  if (loading && list.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (err.isNotEmpty && list.isEmpty) {
                    return Center(child: Text(err));
                  }
                  if (list.isEmpty) {
                    return const CustomNoData();
                  }

                  return Padding(
                    padding: edgePadding.copyWith(top: 0),
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, idx) {
                        return _VideoTransTaskCard(ctrl: ctrl, item: list[idx]);
                      },
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
