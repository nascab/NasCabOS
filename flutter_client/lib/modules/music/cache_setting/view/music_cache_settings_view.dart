import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../utils/device_utils.dart';
import '../../../../utils/file_util.dart';
import '../../../../utils/toast_util.dart';
import '../controller/music_cache_settings_controller.dart';

class MusicCacheSettingsView extends StatefulWidget {
  const MusicCacheSettingsView({super.key});

  @override
  State<MusicCacheSettingsView> createState() => _MusicCacheSettingsViewState();
}

class _MusicCacheSettingsViewState extends State<MusicCacheSettingsView> {
  final TextEditingController _maxItemsCtrl = TextEditingController();

  @override
  void dispose() {
    _maxItemsCtrl.dispose();
    super.dispose();
  }

  int? _parseMaxItems() {
    final raw = _maxItemsCtrl.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final customColors = Theme.of(context).extension<CustomColors>();

    return GetBuilder<MusicCacheSettingsController>(
      init: MusicCacheSettingsController(),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  DeviceUtils.isMobile ? 0 : 12,
                  16,
                  DeviceUtils.isMobile ? 0 : 10,
                ),
                child: Row(
                  children: [
                    Text(
                      'music_cache_settings_title'.tr,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: 'refresh'.tr,
                      onPressed: () => ctrl.refreshStats(showLoading: true),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Obx(() {
                  final enabled = ctrl.enabled.value;
                  final maxItems = ctrl.maxItems.value;
                  if (_maxItemsCtrl.text.trim() != maxItems.toString()) {
                    _maxItemsCtrl.text = maxItems.toString();
                  }

                  final cachedCount = ctrl.cachedCount.value;
                  final cachedBytes = ctrl.cachedBytes.value;
                  final loading = ctrl.loading.value;
                  final clearing = ctrl.clearing.value;

                  return Stack(
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          CustomGlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.tune_rounded, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'music_cache_settings_section_options'.tr,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SwitchListTile(
                                  activeColor: theme.colorScheme.primary,
                                  contentPadding: EdgeInsets.zero,
                                  value: enabled,
                                  onChanged: (v) => ctrl.toggleEnabled(v),
                                  title: Text(
                                    'music_cache_settings_enabled'.tr,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  subtitle: Text(
                                    'music_cache_settings_enabled_tip'.tr,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _maxItemsCtrl,
                                        enabled: enabled,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              signed: false,
                                              decimal: false,
                                            ),
                                        decoration: InputDecoration(
                                          labelText:
                                              'music_cache_settings_max_items'
                                                  .tr,
                                          border: const OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) async {
                                          final v = _parseMaxItems();
                                          if (v == null || v < 0) {
                                            ToastUtil.show(
                                              'music_cache_settings_invalid_max_items'
                                                  .tr,
                                            );
                                            return;
                                          }
                                          await ctrl.setMaxItems(v);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      height: 45,
                                      child: CustomButton(
                                        onPressed: enabled
                                            ? () async {
                                                final v = _parseMaxItems();
                                                if (v == null || v < 0) {
                                                  ToastUtil.show(
                                                    'music_cache_settings_invalid_max_items'
                                                        .tr,
                                                  );
                                                  return;
                                                }
                                                await ctrl.setMaxItems(v);
                                              }
                                            : null,
                                        text: 'music_cache_settings_apply'.tr,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          CustomGlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.storage_rounded,
                                        size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'music_cache_settings_section_stats'.tr,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatTile(
                                        label:
                                            'music_cache_settings_cached_count'
                                                .tr,
                                        value: cachedCount.toString(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _StatTile(
                                        label:
                                            'music_cache_settings_cached_size'
                                                .tr,
                                        value: FileUtil.formatSize(cachedBytes),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.tonal(
                                    onPressed: clearing
                                        ? null
                                        : () async {
                                            await ctrl.clearCache();
                                            ToastUtil.show(
                                              'operation_success'.tr,
                                            );
                                          },
                                    child: Text(
                                      clearing
                                        ? 'music_cache_settings_clearing'.tr
                                        : 'music_cache_settings_clear'.tr,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (loading)
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    return CustomGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 6),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
