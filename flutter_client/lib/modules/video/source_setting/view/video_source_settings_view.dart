import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_checkbox.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../base/components/custom_switch.dart';
import '../../../files/views/folder_picker_dialog.dart';
import '../../../../utils/dialog_util.dart';
import '../controller/video_source_settings_controller.dart';
import '../models/video_source.dart';

const double _kBaseCardWidth = 400;
const double _kCardHeight = 380;

class VideoSourceSettingsView extends StatelessWidget {
  const VideoSourceSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = Theme.of(context).extension<CustomColors>();
    final isNarrow = DeviceUtils.isMobile;
    return GetBuilder<VideoSourceSettingsController>(
      init: VideoSourceSettingsController(),
      builder: (ctrl) {
        return Container(
          color: customColors?.mainContentBgColor,
          child: isNarrow
              ? Obx(() {
                  final items = ctrl.sources.toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'settings_source'.tr,
                            style: theme.textTheme.titleMedium,
                          ),
                          TextButton(
                            onPressed: () => ctrl.scanSource('all'),
                            child: Text('video_source_scan_all'.tr),
                          ),
                          Tooltip(
                            message: 'photo_source_reset_thumbnails_tooltip'.tr,
                            child: TextButton(
                              onPressed: () => ctrl.preGenerateThumbnails(),
                              child: Text('photo_source_reset_thumbnails'.tr),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final s in items) ...[
                        _MobileSourceCard(source: s),
                        const SizedBox(height: 12),
                      ],
                      _MobileAddSourceCard(
                        onTap: () => _pickAndAdd(context, ctrl),
                      ),
                    ],
                  );
                })
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Row(
                        children: [
                          Text(
                            'settings_source'.tr,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(width: 10),
                          TextButton(
                            onPressed: () => ctrl.scanSource('all'),
                            child: Text('video_source_scan_all'.tr),
                          ),
                          Tooltip(
                            message: 'photo_source_reset_thumbnails_tooltip'.tr,
                            child: TextButton(
                              onPressed: () => ctrl.preGenerateThumbnails(),
                              child: Text('photo_source_reset_thumbnails'.tr),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Obx(() {
                        final items = ctrl.sources.toList();
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            const paddingX = 10.0;
                            const spacing = 8.0;
                            final availableWidth =
                                (constraints.maxWidth - paddingX * 2).clamp(
                                  0,
                                  99999,
                                );
                            final count =
                                (((availableWidth + spacing) /
                                            (_kBaseCardWidth + spacing))
                                        .floor())
                                    .clamp(1, 99);

                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: count,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                    mainAxisExtent: _kCardHeight,
                                  ),
                              itemCount: items.length + 1,
                              itemBuilder: (context, index) {
                                if (index < items.length) {
                                  return _SourceCard(source: items[index]);
                                }
                                return _AddSourceCard(
                                  onTap: () => _pickAndAdd(context, ctrl),
                                );
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _pickAndAdd(
    BuildContext context,
    VideoSourceSettingsController ctrl,
  ) async {
    final result = await _showAddSourceDialog(context);
    if (result == null) return;
    await ctrl.addSource(
      result.path,
      mediaType: result.mediaType,
      matchNfo: result.matchNfo ? 1 : 0,
    );
  }

  Future<_AddSourceDialogResult?> _showAddSourceDialog(BuildContext context) {
    final theme = Theme.of(context);
    String selectedPath = '';
    String mediaType = 'movie';
    bool matchNfo = false;

    return showDialog<_AddSourceDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('video_source_add_dialog_title'.tr),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: selectedPath.isEmpty ? '' : selectedPath,
                            child: Text(
                              selectedPath.isEmpty
                                  ? 'video_source_add_path_empty'.tr
                                  : selectedPath,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: selectedPath.isEmpty
                                    ? theme.colorScheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () async {
                            final selected = await showFolderPickerBottomSheet(
                              ctx,
                              multiSelect: false,
                              allowFileSelect: false,
                            );
                            if (selected == null || selected.isEmpty) return;
                            setState(() {
                              selectedPath = selected.first.trim();
                            });
                          },
                          child: Text('video_source_add_pick_path'.tr),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'video_source_add_media_type_title'.tr,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'video_source_add_media_type_subtitle_movie'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      'video_source_add_media_type_subtitle_tv'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'movie',
                            groupValue: mediaType,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('video_source_add_media_type_movie'.tr),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => mediaType = v);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'tv',
                            groupValue: mediaType,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('video_source_add_media_type_tv'.tr),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => mediaType = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'video_source_add_match_nfo_title'.tr,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        CustomSwitch(
                          value: matchNfo,
                          onChanged: (v) => setState(() => matchNfo = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedPath.trim().isEmpty) {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: 'video_source_add_path_required'.tr,
                        buttonText: 'ok'.tr,
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _AddSourceDialogResult(
                        path: selectedPath.trim(),
                        mediaType: mediaType,
                        matchNfo: matchNfo,
                      ),
                    );
                  },
                  child: Text('video_source_add_submit'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AddSourceDialogResult {
  final String path;
  final String mediaType;
  final bool matchNfo;

  const _AddSourceDialogResult({
    required this.path,
    required this.mediaType,
    required this.matchNfo,
  });
}

class _MobileAddSourceCard extends StatelessWidget {
  final VoidCallback onTap;

  const _MobileAddSourceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('video_source_add_card'.tr, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _MobileSourceCard extends StatelessWidget {
  final VideoSource source;

  const _MobileSourceCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = Get.find<VideoSourceSettingsController>();

    final intervalEnabled = ctrl.getIntervalEnabled(source);
    final hours = ctrl.getIntervalHours(source).clamp(1, 24);
    final availability = source.exists
        ? 'video_source_available'.tr
        : 'video_source_unavailable'.tr;

    Future<void> relocate() async {
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'photo_source_relocate_confirm'.tr,
        confirmText: 'confirm'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed != true) return;
      if (!context.mounted) return;

      final selected = await showFolderPickerBottomSheet(
        context,
        multiSelect: false,
        allowFileSelect: false,
      );
      if (selected == null || selected.isEmpty) return;
      await ctrl.relocateSource(source, selected.first);
    }

    Future<void> delete() async {
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'video_source_delete_confirm'.trParams({'path': source.path}),
        confirmText: 'confirm'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed == true) {
        await ctrl.deleteSourceOptimistic(source);
      }
    }

    Future<void> scanNow() async {
      await ctrl.scanSource(source.path);
    }

    Future<void> onChangeMediaType(String mediaType) async {
      if (source.mediaType == mediaType) return;
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'video_source_change_media_type_confirm'.tr,
        confirmText: 'confirm'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed != true) return;
      await ctrl.updateMediaTypeOptimistic(source, mediaType);
    }

    Widget switchRow({
      required String title,
      required bool value,
      required String helpMessage,
      required ValueChanged<bool> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(title)),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: helpMessage,
                    onPressed: () {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: helpMessage,
                        buttonText: 'ok'.tr,
                      );
                    },
                    icon: Icon(
                      Icons.help_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            CustomSwitch(value: value, onChanged: onChanged),
          ],
        ),
      );
    }

    return CustomGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.path,
              style: theme.textTheme.titleMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '[$availability]',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: source.exists ? Colors.green : Colors.red,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  children: [
                    if (!source.exists)
                      TextButton(
                        onPressed: relocate,
                        child: Text('photo_source_relocate'.tr),
                      ),
                    if (source.exists)
                      TextButton(
                        onPressed: scanNow,
                        child: Text('video_source_scan_now'.tr),
                      ),
                    TextButton(
                      onPressed: delete,
                      child: Text(
                        'delete'.tr,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'video_source_media_type'.tr,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('video_source_media_type_movie'.tr),
                      selected: source.mediaType == 'movie',
                      onSelected: (v) {
                        if (v) onChangeMediaType('movie');
                      },
                    ),
                    ChoiceChip(
                      label: Text('video_source_media_type_tv'.tr),
                      selected: source.mediaType == 'tv',
                      onSelected: (v) {
                        if (v) onChangeMediaType('tv');
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            switchRow(
              title: 'video_source_match_nfo'.tr,
              value: source.matchNfo == 1,
              helpMessage: 'video_source_help_match_nfo'.tr,
              onChanged: (v) =>
                  ctrl.updateMatchNfoOptimistic(source, v ? 1 : 0),
            ),
            switchRow(
              title: 'video_source_scan_when_start'.tr,
              value: source.scanWhenStart == 1,
              helpMessage: 'video_source_help_scan_when_start'.tr,
              onChanged: (v) =>
                  ctrl.updateSourceOptimistic(source, scanWhenStart: v ? 1 : 0),
            ),
            switchRow(
              title: 'video_source_scan_when_change'.tr,
              value: source.scanWhenChange == 1,
              helpMessage: 'video_source_help_scan_when_change'.tr,
              onChanged: (v) => ctrl.updateSourceOptimistic(
                source,
                scanWhenChange: v ? 1 : 0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: Text('video_source_scan_interval'.tr)),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip: 'video_source_help_scan_interval'.tr,
                          onPressed: () {
                            DialogUtil.showInfoDialog(
                              title: 'tip'.tr,
                              content: 'video_source_help_scan_interval'.tr,
                              buttonText: 'ok'.tr,
                            );
                          },
                          icon: Icon(
                            Icons.help_outline,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CustomSwitch(
                    value: intervalEnabled,
                    onChanged: (v) {
                      if (v) {
                        final ms = hours * 3600 * 1000;
                        ctrl.updateSourceOptimistic(
                          source,
                          scanInterval: 1,
                          scanIntervalMs: ms,
                        );
                      } else {
                        ctrl.updateSourceOptimistic(
                          source,
                          scanInterval: 0,
                          scanIntervalMs: 0,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            if (intervalEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Text('video_source_scan_interval_hours'.tr),
                    const Spacer(),
                    DropdownButton<int>(
                      value: hours,
                      items: List.generate(
                        24,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        ctrl.updateSourceOptimistic(
                          source,
                          scanInterval: 1,
                          scanIntervalMs: v * 3600 * 1000,
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddSourceCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomGlassCard(
      onTap: onTap,
      child: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 38,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'video_source_add_card'.tr,
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  IconButton(
                    tooltip: 'video_source_help_add_source'.tr,
                    onPressed: () {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: 'video_source_help_add_source'.tr,
                        buttonText: 'ok'.tr,
                      );
                    },
                    icon: Icon(
                      Icons.help_outline,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final VideoSource source;

  const _SourceCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = Get.find<VideoSourceSettingsController>();

    final intervalEnabled = ctrl.getIntervalEnabled(source);
    final hours = ctrl.getIntervalHours(source);
    Future<void> onChangeMediaType(String mediaType) async {
      if (source.mediaType == mediaType) return;
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'video_source_change_media_type_confirm'.tr,
        confirmText: 'confirm'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed != true) return;
      await ctrl.updateMediaTypeOptimistic(source, mediaType);
    }

    return CustomGlassCard(
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (!source.exists) ...[
                        TextButton(
                          onPressed: () async {
                            final confirmed =
                                await DialogUtil.showConfirmDialog(
                                  title: 'need_confirm'.tr,
                                  content: 'photo_source_relocate_confirm'.tr,
                                  confirmText: 'confirm'.tr,
                                  cancelText: 'cancel'.tr,
                                );
                            if (confirmed != true) return;
                            if (!context.mounted) return;

                            final selected = await showFolderPickerBottomSheet(
                              context,
                              multiSelect: false,
                              allowFileSelect: false,
                            );
                            if (selected == null || selected.isEmpty) return;
                            await ctrl.relocateSource(source, selected.first);
                          },
                          child: Text('photo_source_relocate'.tr),
                        ),
                      ],
                      Text(
                        '[${(source.exists ? 'video_source_available' : 'video_source_unavailable').tr}]',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: source.exists ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: source.path,
                          child: Text(
                            source.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                CustomBorderedIconButton(
                  tooltip: 'video_source_scan_now'.tr,
                  icon: Icons.refresh,
                  onTap: () => ctrl.scanSource(source.path),
                ),
                const SizedBox(width: 6),
                CustomBorderedIconButton(
                  tooltip: 'delete'.tr,
                  icon: Icons.delete_outline,
                  onTap: () async {
                    final confirmed = await DialogUtil.showConfirmDialog(
                      title: 'need_confirm'.tr,
                      content: 'video_source_delete_confirm'.trParams({
                        'path': source.path,
                      }),
                      confirmText: 'confirm'.tr,
                      cancelText: 'cancel'.tr,
                    );
                    if (confirmed != true) return;
                    await ctrl.deleteSourceOptimistic(source);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text('video_source_media_type'.tr),
                            IconButton(
                              tooltip:
                                  '${'video_source_add_media_type_subtitle_movie'.tr}\n${'video_source_add_media_type_subtitle_tv'.tr}',
                              onPressed: () {
                                DialogUtil.showInfoDialog(
                                  title: 'tip'.tr,
                                  content:
                                      '${'video_source_add_media_type_subtitle_movie'.tr}\n${'video_source_add_media_type_subtitle_tv'.tr}',
                                  buttonText: 'ok'.tr,
                                );
                              },
                              icon: Icon(
                                Icons.help_outline,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomCheckbox(
                          value: source.mediaType == 'movie',
                          onChanged: (v) {
                            if (v != true) return;
                            onChangeMediaType('movie');
                          },
                        ),
                        InkWell(
                          onTap: () => onChangeMediaType('movie'),
                          child: Text('video_source_media_type_movie'.tr),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomCheckbox(
                          value: source.mediaType == 'tv',
                          onChanged: (v) {
                            if (v != true) return;
                            onChangeMediaType('tv');
                          },
                        ),
                        InkWell(
                          onTap: () => onChangeMediaType('tv'),
                          child: Text('video_source_media_type_tv'.tr),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            _switchRow(
              title: 'video_source_match_nfo'.tr,
              value: source.matchNfo == 1,
              helpMessage: 'video_source_help_match_nfo'.tr,
              helpIconColor: theme.colorScheme.onSurfaceVariant,
              onChanged: (v) =>
                  ctrl.updateMatchNfoOptimistic(source, v ? 1 : 0),
            ),
            const SizedBox(height: 6),
            _switchRow(
              title: 'video_source_scan_when_start'.tr,
              value: source.scanWhenStart == 1,
              helpMessage: 'video_source_help_scan_when_start'.tr,
              helpIconColor: theme.colorScheme.onSurfaceVariant,
              onChanged: (v) =>
                  ctrl.updateSourceOptimistic(source, scanWhenStart: v ? 1 : 0),
            ),
            const SizedBox(height: 6),
            _switchRow(
              title: 'video_source_scan_when_change'.tr,
              value: source.scanWhenChange == 1,
              helpMessage: 'video_source_help_scan_when_change'.tr,
              helpIconColor: theme.colorScheme.onSurfaceVariant,
              onChanged: (v) => ctrl.updateSourceOptimistic(
                source,
                scanWhenChange: v ? 1 : 0,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text('video_source_scan_interval'.tr),
                            IconButton(
                              tooltip: 'video_source_help_scan_interval'.tr,
                              onPressed: () {
                                DialogUtil.showInfoDialog(
                                  title: 'tip'.tr,
                                  content: 'video_source_help_scan_interval'.tr,
                                  buttonText: 'ok'.tr,
                                );
                              },
                              icon: Icon(
                                Icons.help_outline,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                CustomSwitch(
                  value: intervalEnabled,
                  onChanged: (v) {
                    if (v) {
                      final ms = hours.clamp(1, 24) * 3600 * 1000;
                      ctrl.updateSourceOptimistic(
                        source,
                        scanInterval: 1,
                        scanIntervalMs: ms,
                      );
                    } else {
                      ctrl.updateSourceOptimistic(
                        source,
                        scanInterval: 0,
                        scanIntervalMs: 0,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: intervalEnabled
                  ? Row(
                      key: const ValueKey('interval'),
                      children: [
                        Text('video_source_scan_interval_hours'.tr),
                        const Spacer(),
                        DropdownButton<int>(
                          value: hours.clamp(1, 24),
                          items: List.generate(
                            24,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            ctrl.updateSourceOptimistic(
                              source,
                              scanInterval: 1,
                              scanIntervalMs: v * 3600 * 1000,
                            );
                          },
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required String helpMessage,
    required Color helpIconColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(title),
              IconButton(
                tooltip: helpMessage,
                onPressed: () {
                  DialogUtil.showInfoDialog(
                    title: 'tip'.tr,
                    content: helpMessage,
                    buttonText: 'ok'.tr,
                  );
                },
                icon: Icon(
                  Icons.help_outline,
                  size: 18,
                  color: helpIconColor,
                ),
              ),
            ],
          ),
        ),
        CustomSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
