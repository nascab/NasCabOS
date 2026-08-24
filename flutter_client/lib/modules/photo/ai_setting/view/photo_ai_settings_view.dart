import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_dropdown_field.dart';
import '../../../base/components/custom_switch.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../core/api/api_controller.dart';
import '../controller/photo_ai_settings_controller.dart';

class PhotoAiSettingsView extends StatelessWidget {
  const PhotoAiSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final isNarrow = DeviceUtils.isMobile;
    return GetBuilder<PhotoAiSettingsController>(
      init: PhotoAiSettingsController(),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, isNarrow ? 12 : 12, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'photo_ai_settings_title'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        tooltip: 'help'.tr,
                        onPressed: () {
                          DialogUtil.showInfoDialog(
                            title: 'tip'.tr,
                            content: 'photo_ai_settings_help_content'.tr,
                          );
                        },
                        icon: const Icon(Icons.help_outline),
                      ),
                      IconButton(
                        tooltip: 'refresh'.tr,
                        onPressed: () => ctrl.fetchSettings(showLoading: true),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 2),
                      // GPU 优先开关（需要服务器版本 >= 10）
                      if (ApiController.instance.isServerVersionAtLeast(10))
                        CustomGlassCard(
                          child: Obx(() {
                            return _SwitchItem(
                              title: 'photo_ai_gpu_prefer'.tr,
                              subtitle: 'photo_ai_gpu_prefer_subtitle'.tr,
                              value: ctrl.gpuPrefer.value,
                              enabled: ctrl.canEdit,
                              onChanged: (v) => ctrl.toggleGpu(v),
                            );
                          }),
                        ),
                      if (ApiController.instance.isServerVersionAtLeast(10))
                        const SizedBox(height: 12),
                      CustomGlassCard(
                        child: Column(
                          children: [
                            Obx(() {
                              return _SwitchItem(
                                title: 'photo_ai_enable_ocr'.tr,
                                subtitle: 'photo_ai_enable_ocr_subtitle'.tr,
                                progressPercent: ctrl.ocrProgress.value,
                                value: ctrl.ocrEnabled.value,
                                enabled: ctrl.canEdit,
                                onChanged: (v) => ctrl.toggleOcr(v),
                              );
                            }),
                            const Divider(height: 1),
                            // Obx(() {
                            //   return _SwitchItem(
                            //     title: 'photo_ai_enable_pet'.tr,
                            //     value: ctrl.petEnabled.value,
                            //     enabled: ctrl.canEdit,
                            //     onChanged: (v) => ctrl.togglePet(v),
                            //   );
                            // }),
                            // const Divider(height: 1),
                            Obx(() {
                              return _SwitchItem(
                                title: 'photo_ai_enable_scene'.tr,
                                subtitle: 'photo_ai_enable_scene_subtitle'.tr,
                                progressPercent: ctrl.placeProgress.value,
                                value: ctrl.placeEnabled.value,
                                enabled: ctrl.canEdit,
                                onChanged: (v) => ctrl.togglePlace(v),
                              );
                            }),
                            const Divider(height: 1),
                            Obx(() {
                              return _SimilarDedupItem(
                                value: ctrl.similarEnabled.value,
                                scanPercent: ctrl.similarScanProgress.value,
                                comparePercent:
                                    ctrl.similarCompareProgress.value,
                                enabled: ctrl.canEdit,
                                onChanged: (v) => ctrl.toggleSimilar(v),
                                onReset: () => ctrl.resetSimilar(),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomGlassCard(
                        child: Column(
                          children: [
                            Obx(() {
                              return _SwitchItem(
                                title: 'photo_ai_enable_face'.tr,
                                progressPercent: ctrl.faceProgress.value,
                                value: ctrl.faceEnabled.value,
                                enabled: ctrl.canEdit,
                                onChanged: (v) => ctrl.toggleFace(v),
                              );
                            }),
                            const Divider(height: 1),
                            Obx(() {
                              return _AutoHideFacesItem(
                                value: ctrl.faceMinShowCount.value,
                                enabled: ctrl.canEdit,
                                onChanged: (v) => ctrl.setFaceMinShowCount(v),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SwitchItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int? progressPercent;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SwitchItem({
    required this.title,
    this.subtitle,
    this.progressPercent,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleText = subtitle;
    final p = progressPercent;
    final showProgress = p != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (showProgress) SizedBox(width: 8),
                    if (showProgress)
                      Text(
                        'photo_ai_progress_suffix'.trParams({
                          'percent': p.clamp(0, 100).toString(),
                        }),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                if (subtitleText != null && subtitleText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          CustomSwitch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

class _AutoHideFacesItem extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _AutoHideFacesItem({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withOpacity(0.5);

    const options = [0, 3, 5, 10];
    final shown = options.contains(value) ? value : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'photo_ai_auto_hide_face_album'.tr,
            style: theme.textTheme.titleSmall?.copyWith(color: fg),
          ),
          const SizedBox(height: 4),
          Text(
            'photo_ai_auto_hide_face_album_subtitle'.tr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fg.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final fieldWidth = maxWidth > 360 ? 360.0 : maxWidth;
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: fieldWidth,
                  height: 44,
                  child: CustomDropdownField<int>(
                    value: shown,
                    enabled: enabled,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    items: options
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: e,
                            child: Text(
                              'photo_ai_auto_hide_face_album_option_$e'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      onChanged(v);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SimilarDedupItem extends StatelessWidget {
  final bool value;
  final int scanPercent;
  final int comparePercent;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onReset;

  const _SimilarDedupItem({
    required this.value,
    required this.scanPercent,
    required this.comparePercent,
    required this.enabled,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = scanPercent.clamp(0, 100);
    final compare = comparePercent.clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'photo_ai_enable_similar'.tr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'photo_ai_enable_similar_subtitle'.tr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'photo_ai_similar_scan_progress_suffix'.trParams({
                        'percent': scan.toString(),
                      }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'photo_ai_similar_compare_progress_suffix'.trParams({
                        'percent': compare.toString(),
                      }),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: enabled ? onReset : null,
            child: Text('reset'.tr),
          ),
          const SizedBox(width: 8),
          CustomSwitch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}
