import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_dropdown_field.dart';
import '../../../base/components/custom_glass_card.dart';
import '../controller/photo_preview_settings_controller.dart';

class PhotoPreviewSettingsView extends StatelessWidget {
  const PhotoPreviewSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final isNarrow = DeviceUtils.isMobile;
    return GetBuilder<PhotoPreviewSettingsController>(
      init: PhotoPreviewSettingsController(),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, isNarrow ? 12 : 12, 16, 12),
            child: ListView(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'photo_preview_settings_title'.tr,
                      style: theme.textTheme.titleMedium,
                    ),
                    IconButton(
                      tooltip: 'refresh'.tr,
                      onPressed: () => ctrl.fetchSettings(showLoading: true),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'photo_preview_size_label'.tr,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'photo_preview_size_subtitle'.tr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Obx(() {
                          final value = ctrl.previewSize.value;
                          return CustomDropdownField<String>(
                            value: value,
                            items: PhotoPreviewSettingsController.allowedSizes
                                .map((e) {
                                  final label = e == 'origin'
                                      ? 'photo_preview_size_origin'.tr
                                      : 'photo_preview_size_long_side'.trParams(
                                          {'size': e},
                                        );
                                  return DropdownMenuItem<String>(
                                    value: e,
                                    child: Text(label),
                                  );
                                })
                                .toList(),
                            onChanged: (v) {
                              final next = (v ?? '').trim();
                              if (next.isEmpty) return;
                              ctrl.updatePreviewSize(next);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                if (isNarrow)
                  Obx(() {
                    if (ctrl.previewSize.value == 'origin') {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: CustomGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'photo_preview_wifi_original'.tr,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              'photo_preview_wifi_original_subtitle'.tr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            value: ctrl.wifiOriginalEnabled.value,
                            onChanged: ctrl.setWifiOriginalEnabled,
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
