import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_switch.dart';
import '../../../files/views/folder_picker_dialog.dart';
import '../../../../utils/dialog_util.dart';
import '../controller/video_other_settings_controller.dart';

class VideoOtherSettingsView extends StatelessWidget {
  const VideoOtherSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final isNarrow = DeviceUtils.isMobile;
    return GetBuilder<VideoOtherSettingsController>(
      init: VideoOtherSettingsController(),
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
                        'video_other_settings_title'.tr,
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        tooltip: 'refresh'.tr,
                        onPressed: () async {
                          await ctrl.fetchSettings(showLoading: true);
                          await ctrl.fetchTranscodeSettings(showLoading: true);
                          await ctrl.fetchSubtitleSettings(showLoading: true);
                        },
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
                      CustomGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'video_scrape_settings_title'.tr,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 12),
                              _TokenField(ctrl: ctrl),
                              const SizedBox(height: 12),
                              _LanguageField(ctrl: ctrl),
                              const SizedBox(height: 12),
                              _ProxyToggle(ctrl: ctrl),
                              Obx(() {
                                if (!ctrl.proxyEnabled.value) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  children: [
                                    const SizedBox(height: 10),
                                    _ProxyField(ctrl: ctrl),
                                  ],
                                );
                              }),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton(
                                  onPressed: () => ctrl.saveSettings(),
                                  child: Text('save'.tr),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'video_subtitle_settings_title'.tr,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 12),
                              _SubtitlePreExtractToggle(ctrl: ctrl),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton(
                                  onPressed: () => ctrl.saveSubtitleSettings(),
                                  child: Text('save'.tr),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'video_transcode_settings_title'.tr,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 12),
                              _TranscodeHwDecoderField(ctrl: ctrl),
                              const SizedBox(height: 12),
                              _TranscodeTempDirField(ctrl: ctrl),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton(
                                  onPressed: () => ctrl.saveTranscodeSettings(),
                                  child: Text('save'.tr),
                                ),
                              ),
                            ],
                          ),
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

class _TranscodeHwDecoderField extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _TranscodeHwDecoderField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final options = ctrl.availableHwDecoders.toList(growable: false);
      final currentValue =
          ctrl.findHwDecoderOption(ctrl.preferredHwDecoder.value) != null
          ? ctrl.preferredHwDecoder.value
          : '';
      final selectedOption = ctrl.findHwDecoderOption(currentValue);
      final effectiveLabel = ctrl.effectiveHwDecoderLabel.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'video_transcode_hwaccel_preferred'.tr,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'video_transcode_hwaccel_preferred_tip'.tr,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (options.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.memory_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'video_transcode_hwaccel_none'.tr,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: currentValue,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(value: '', child: Text('auto'.tr)),
                ...options.map(
                  (option) => DropdownMenuItem(
                    value: option.key,
                    child: Text(option.label),
                  ),
                ),
              ],
              onChanged: (value) => ctrl.setPreferredHwDecoder(value ?? ''),
            ),
          if (options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectedOption != null)
                      Text(
                        '${selectedOption.label} · ${ctrl.buildHwDecoderSummary(selectedOption)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (effectiveLabel.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          top: selectedOption != null ? 6 : 0,
                        ),
                        child: Text(
                          '${'video_transcode_hwaccel_current'.tr}: $effectiveLabel',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (selectedOption == null && effectiveLabel.isEmpty)
                      Text('auto'.tr, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _TranscodeTempDirField extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _TranscodeTempDirField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final dir = ctrl.transcodeTempDir.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'video_transcode_temp_dir'.tr,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'video_transcode_temp_dir_tip'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showFolderPickerBottomSheet(
                    context,
                    multiSelect: false,
                    allowFileSelect: false,
                    initialPath: dir.isNotEmpty ? dir : null,
                  );
                  final chosen = (picked ?? []).isNotEmpty ? picked!.first : '';
                  if (chosen.isNotEmpty) {
                    ctrl.setTranscodeTempDirDraft(chosen);
                  }
                },
                child: Text('select'.tr),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  ctrl.resetTranscodeTempDirDraft();
                },
                child: Text('reset'.tr),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              dir.isNotEmpty ? dir : 'default'.tr,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    });
  }
}

class _TokenField extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _TokenField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'video_tmdb_access_token'.tr,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'video_tmdb_access_token_help'.tr,
              waitDuration: const Duration(milliseconds: 200),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    DialogUtil.showInfoDialog(
                      title: 'tip'.tr,
                      content: 'video_tmdb_access_token_help'.tr,
                    );
                  },
                  child: Icon(Icons.help_outline, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl.tmdbTokenController,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'video_tmdb_access_token_hint'.tr,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _SubtitlePreExtractToggle extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _SubtitlePreExtractToggle({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final enabled = ctrl.subtitlePreExtractEnabled.value;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'video_subtitle_pre_extract_enable'.tr,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text('process.worker.subtitlePreExtract.purpose'.tr),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CustomSwitch(
            value: enabled,
            onChanged: (v) => ctrl.subtitlePreExtractEnabled.value = v,
          ),
        ],
      );
    });
  }
}

class _ProxyToggle extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _ProxyToggle({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final enabled = ctrl.proxyEnabled.value;
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'video_tmdb_proxy_enable'.tr,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text('video_tmdb_proxy_enable_tip'.tr),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CustomSwitch(
            value: enabled,
            onChanged: (v) => ctrl.proxyEnabled.value = v,
          ),
        ],
      );
    });
  }
}

class _LanguageField extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _LanguageField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: '',
        child: Text('video_tmdb_language_follow_system'.tr),
      ),
      DropdownMenuItem(
        value: 'en-US',
        child: Text('video_tmdb_language_en'.tr),
      ),
      DropdownMenuItem(
        value: 'zh-CN',
        child: Text('video_tmdb_language_zh'.tr),
      ),
      DropdownMenuItem(
        value: 'es-ES',
        child: Text('video_tmdb_language_es'.tr),
      ),
      DropdownMenuItem(
        value: 'fr-FR',
        child: Text('video_tmdb_language_fr'.tr),
      ),
      DropdownMenuItem(
        value: 'de-DE',
        child: Text('video_tmdb_language_de'.tr),
      ),
      DropdownMenuItem(
        value: 'ja-JP',
        child: Text('video_tmdb_language_ja'.tr),
      ),
      DropdownMenuItem(
        value: 'pt-BR',
        child: Text('video_tmdb_language_pt'.tr),
      ),
      DropdownMenuItem(
        value: 'ru-RU',
        child: Text('video_tmdb_language_ru'.tr),
      ),
      DropdownMenuItem(
        value: 'ar-SA',
        child: Text('video_tmdb_language_ar'.tr),
      ),
      DropdownMenuItem(
        value: 'ko-KR',
        child: Text('video_tmdb_language_ko'.tr),
      ),
      DropdownMenuItem(
        value: 'th-TH',
        child: Text('video_tmdb_language_th'.tr),
      ),
      DropdownMenuItem(
        value: 'vi-VN',
        child: Text('video_tmdb_language_vi'.tr),
      ),
      DropdownMenuItem(
        value: 'id-ID',
        child: Text('video_tmdb_language_id'.tr),
      ),
    ];

    return Obx(() {
      final value = ctrl.tmdbLanguage.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('video_tmdb_language'.tr, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: value,
            items: items,
            onChanged: (v) => ctrl.tmdbLanguage.value = (v ?? '').trim(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      );
    });
  }
}

class _ProxyField extends StatelessWidget {
  final VideoOtherSettingsController ctrl;

  const _ProxyField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('video_tmdb_proxy_url'.tr, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl.proxyUrlController,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'video_tmdb_proxy_url_hint'.tr,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Text('video_tmdb_proxy_save_tip'.tr),
      ],
    );
  }
}
