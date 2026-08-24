import 'dart:math' as math;

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../base/components/custom_hover_select_menu.dart';
import '../../../base/components/custom_glass_card.dart';
import '../../../files/views/pc_components/pc_file_drop_target.dart';
import '../../../transfer/controllers/upload_parts/upload_web_file_helper.dart';
import '../../../transfer/controllers/upload_parts/upload_web_folder_drop_target_wrapper.dart';
import 'app_image_compress_upload_picker.dart';
import '../controller/image_compress_controller.dart';

class ImageCompressView extends StatefulWidget {
  final bool appMode;
  const ImageCompressView({super.key, this.appMode = false});

  @override
  State<ImageCompressView> createState() => _ImageCompressViewState();
}

class _ImageCompressViewState extends State<ImageCompressView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ImageCompressController>(
      init: ImageCompressController(),
      builder: (ctrl) {
        return Obx(() {
          ctrl.busy.value;
          ctrl.dragHover.value;
          ctrl.quality.value;
          ctrl.format.value;
          ctrl.size.value;
          ctrl.customOutSize.value;
          ctrl.withMeta.value;
          final customColors = Theme.of(context).extension<CustomColors>();
          return Container(
            color: customColors?.mainContentBgColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: !widget.appMode,
                    controller: _scrollController,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          sliver: SliverToBoxAdapter(
                            child: _UploadSection(
                              ctrl: ctrl,
                              appMode: widget.appMode,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          sliver: SliverToBoxAdapter(
                            child: _StatsBar(ctrl: ctrl),
                          ),
                        ),
                        if (ctrl.results.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: Text('no_data'.tr)),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            sliver: SliverList.separated(
                              itemCount: ctrl.results.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = ctrl.results[index];
                                return _ResultItem(ctrl: ctrl, item: item);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _UploadSection extends StatelessWidget {
  final ImageCompressController ctrl;
  final bool appMode;
  const _UploadSection({required this.ctrl, required this.appMode});

  @override
  Widget build(BuildContext context) {
    if (appMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppImageCompressUploadPicker(
            onPick: () => ctrl.pickAndUploadByMobileSource(context),
            loading: ctrl.busy.value,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _QualityMenu(ctrl: ctrl),
              _FormatMenu(ctrl: ctrl),
              _SizeMenu(ctrl: ctrl),
              _MetaMenu(ctrl: ctrl),
            ],
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final borderColor = ctrl.dragHover.value
        ? theme.colorScheme.primary
        : theme.dividerColor.withValues(alpha: 0.6);
    final boxBg = ctrl.dragHover.value
        ? theme.colorScheme.primary.withValues(alpha: 0.06)
        : theme.colorScheme.surface.withValues(alpha: 0.6);

    final body = Container(
      height: 220,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: borderColor,
                strokeWidth: 1.2,
                radius: 12,
                dash: 8,
                gap: 6,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/file/drag_upload.png',
                  width: 54,
                  height: 54,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.upload_file_outlined,
                      size: 54,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  ctrl.dragHover.value
                      ? 'release_upload'.tr
                      : 'media_tool_drop_area_title'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'media_tool_drop_area_subtitle'.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (ctrl.busy.value)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
    );

    final clickable = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: ctrl.busy.value ? null : ctrl.pickAndUploadImages,
        onSecondaryTap: ctrl.busy.value ? null : () => _pickDialog(context),
        child: body,
      ),
    );

    bool isImageName(String name) {
      final n = name.toLowerCase();
      return n.endsWith('.jpg') ||
          n.endsWith('.jpeg') ||
          n.endsWith('.png') ||
          n.endsWith('.webp') ||
          n.endsWith('.gif') ||
          n.endsWith('.bmp') ||
          n.endsWith('.tif') ||
          n.endsWith('.tiff') ||
          n.endsWith('.heic') ||
          n.endsWith('.heif');
    }

    final dropArea = DeviceUtils.isWeb
        ? UploadWebFolderDropTargetWrapper(
            child: clickable,
            onDragEntered: () {
              if (!ctrl.dragHover.value) ctrl.dragHover.value = true;
            },
            onDragExited: () {
              if (ctrl.dragHover.value) ctrl.dragHover.value = false;
            },
            onDropDataTransfer: (transfer) async {
              if (ctrl.busy.value) return;
              if (ctrl.dragHover.value) ctrl.dragHover.value = false;

              final items = await UploadWebFileHelper.getFilesFromDataTransfer(
                transfer,
              );
              if (items.isEmpty) return;

              final out = <MediaToolImageCompressWebFileBytes>[];
              var hasUnsupported = false;
              for (final it in items) {
                final file = it['file'];
                if (file == null) continue;

                final name = UploadWebFileHelper.getFileName(file);
                if (name.trim().isEmpty) continue;
                if (!isImageName(name)) {
                  hasUnsupported = true;
                  continue;
                }

                try {
                  final bytes = await UploadWebFileHelper.readFileBytes(file);
                  if (bytes.isEmpty) continue;
                  out.add(
                    MediaToolImageCompressWebFileBytes(
                      name: name,
                      bytes: bytes,
                    ),
                  );
                } catch (_) {}
              }

              if (out.isEmpty) {
                if (hasUnsupported) {
                  ToastUtil.show('file_format_not_supported'.tr);
                }
                return;
              }
              if (hasUnsupported) {
                ToastUtil.show('file_format_not_supported'.tr);
              }
              await ctrl.uploadDroppedWebBytes(out);
            },
          )
        : PcFileDropTargetWrapper(
            onDragEntered: () {
              if (!ctrl.dragHover.value) ctrl.dragHover.value = true;
            },
            onDragExited: () {
              if (ctrl.dragHover.value) ctrl.dragHover.value = false;
            },
            onDragDone: (files) async {
              if (ctrl.dragHover.value) ctrl.dragHover.value = false;
              await ctrl.uploadDroppedFiles(files);
            },
            child: clickable,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dropArea,
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _QualityMenu(ctrl: ctrl),
            _FormatMenu(ctrl: ctrl),
            _SizeMenu(ctrl: ctrl),
            _MetaMenu(ctrl: ctrl),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDialog(BuildContext context) async {
    if (ctrl.busy.value) return;
    final showFolder = !DeviceUtils.isWeb;

    final action = await showDialog<_PickAction>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: Text('media_tool_drop_area_title'.tr),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_PickAction.images),
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('media_tool_pick_images'.tr)),
                ],
              ),
            ),
            if (showFolder)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(_PickAction.folder),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('media_tool_pick_folder'.tr)),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Row(
                children: [
                  Icon(
                    Icons.close_outlined,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('cancel'.tr)),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (action == _PickAction.images) {
      await ctrl.pickAndUploadImages();
    } else if (action == _PickAction.folder) {
      await ctrl.pickAndUploadFolder();
    }
  }
}

enum _PickAction { images, folder }

class _MetaMenu extends StatelessWidget {
  final ImageCompressController ctrl;
  const _MetaMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final value = ctrl.withMeta.value ? 'keep' : 'strip';
    return CustomHoverSelectMenu<String>(
      value: value,
      items: [
        CustomHoverSelectMenuItem(
          value: 'keep',
          label: 'media_tool_with_meta'.tr,
          icon: Icons.info_outline,
        ),
        CustomHoverSelectMenuItem(
          value: 'strip',
          label: 'media_tool_without_meta'.tr,
          icon: Icons.do_not_disturb_on_outlined,
        ),
      ],
      onSelected: (v) => ctrl.withMeta.value = v == 'keep',
      buttonIcon: Icons.info_outline,
      radius: 10,
      buttonPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final ImageCompressController ctrl;
  const _StatsBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = ctrl.results.isEmpty || ctrl.busy.value;

    return CustomGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 12,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${'media_tool_optimized'.tr}: ${ctrl.optimizedCount}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (ctrl.optimizedCount > 0)
                  Text(
                    '(${ctrl.optimizedSavedBytesText})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'media_tool_clear'.tr,
            onPressed: disabled ? null : ctrl.clearResults,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'media_tool_download_zip'.tr,
            onPressed: disabled ? null : ctrl.downloadZip,
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
    );
  }
}

class _ResultItem extends StatelessWidget {
  final ImageCompressController ctrl;
  final ImageCompressItem item;
  const _ResultItem({required this.ctrl, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = item.outputSize <= item.inputSize;
    final ratio = item.inputSize <= 0
        ? 0
        : (((item.outputSize - item.inputSize) / item.inputSize) * 100).round();
    final ratioText = '${ratio > 0 ? '+' : ''}$ratio%';
    final ratioColor = ratio <= 0 ? Colors.green : theme.colorScheme.error;
    return CustomGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DownloadTag(
                format: item.outputFormat,
                enabled: !ctrl.busy.value,
                dense: true,
                onTap: () => ctrl.saveFile(item),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${item.inputSizeText} → ${item.outputSizeText}  ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    TextSpan(
                      text: ratioText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ratioColor,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadTag extends StatelessWidget {
  final String format;
  final bool enabled;
  final bool dense;
  final VoidCallback onTap;
  const _DownloadTag({
    required this.format,
    required this.enabled,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = format.trim().isEmpty ? '-' : format.toUpperCase();

    final bg = theme.colorScheme.surfaceContainerHighest;
    final border = theme.dividerColor.withValues(alpha: 0.6);
    final fg = theme.colorScheme.onSurface;
    final iconSize = dense ? 16.0 : 18.0;
    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final textStyle = dense
        ? theme.textTheme.bodySmall
        : theme.textTheme.titleSmall;

    final child = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: enabled ? 1 : 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_rounded,
            size: iconSize,
            color: fg.withValues(alpha: enabled ? 0.85 : 0.35),
          ),
          SizedBox(width: dense ? 6 : 8),
          Text(
            text,
            style: textStyle?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg.withValues(alpha: enabled ? 0.85 : 0.35),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: 'media_tool_save_file'.tr,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: child,
        ),
      ),
    );
  }
}

class _QualityMenu extends StatelessWidget {
  final ImageCompressController ctrl;
  const _QualityMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return CustomHoverSelectMenu<String>(
      value: ctrl.quality.value,
      items: [
        CustomHoverSelectMenuItem(
          value: 'auto',
          label: 'media_tool_auto_quality'.tr,
          icon: Icons.auto_awesome_outlined,
        ),
        for (final q in const [90, 80, 70, 60, 50, 40, 30])
          CustomHoverSelectMenuItem(
            value: q.toString(),
            label: '${'media_tool_quality'.tr} $q',
            icon: Icons.high_quality_outlined,
          ),
      ],
      onSelected: (v) => ctrl.quality.value = v,
      buttonIcon: Icons.high_quality_outlined,
      radius: 10,
      buttonPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

class _FormatMenu extends StatelessWidget {
  final ImageCompressController ctrl;
  const _FormatMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return CustomHoverSelectMenu<String>(
      value: ctrl.format.value,
      items: [
        CustomHoverSelectMenuItem(
          value: 'auto',
          label: 'media_tool_auto_format'.tr,
          icon: Icons.auto_fix_high_outlined,
        ),
        const CustomHoverSelectMenuItem(
          value: 'jpeg',
          label: 'JPEG',
          icon: Icons.image_outlined,
        ),
        const CustomHoverSelectMenuItem(
          value: 'png',
          label: 'PNG',
          icon: Icons.image_outlined,
        ),
        const CustomHoverSelectMenuItem(
          value: 'webp',
          label: 'WEBP',
          icon: Icons.image_outlined,
        ),
      ],
      onSelected: (v) => ctrl.format.value = v,
      buttonIcon: Icons.image_outlined,
      radius: 10,
      buttonPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

class _SizeMenu extends StatelessWidget {
  final ImageCompressController ctrl;
  const _SizeMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final customLabel = ctrl.customOutSize.value == null
        ? 'media_tool_custom_size'.tr
        : '${'media_tool_out_size'.tr} ${ctrl.customOutSize.value}';
    return CustomHoverSelectMenu<String>(
      value: ctrl.size.value,
      items: [
        CustomHoverSelectMenuItem(
          value: 'auto',
          label: 'media_tool_auto_size'.tr,
          icon: Icons.auto_awesome_outlined,
        ),
        for (final s in const [512, 1024, 2048, 4096])
          CustomHoverSelectMenuItem(
            value: s.toString(),
            label: '${'media_tool_out_size'.tr} $s',
            icon: Icons.straighten_outlined,
          ),
        CustomHoverSelectMenuItem(
          value: 'custom',
          label: customLabel,
          icon: Icons.edit_outlined,
        ),
      ],
      onSelected: (v) async {
        if (v == 'custom') {
          final n = await _showSizeDialog(context);
          if (n == null) return;
          ctrl.customOutSize.value = n;
          ctrl.size.value = 'custom';
          return;
        }
        ctrl.size.value = v;
      },
      buttonIcon: Icons.straighten,
      radius: 10,
      buttonPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Future<int?> _showSizeDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final initial = ctrl.customOutSize.value?.toString() ?? '';
    final controller = TextEditingController(text: initial);

    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('media_tool_custom_size'.tr),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'media_tool_out_size_hint'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () {
                final raw = controller.text.trim();
                final n = int.tryParse(raw);
                if (n == null) {
                  Navigator.of(ctx).pop(null);
                  return;
                }
                Navigator.of(ctx).pop(n.clamp(10, 20000));
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dash;
  final double gap;

  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(dash, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        radius != oldDelegate.radius ||
        dash != oldDelegate.dash ||
        gap != oldDelegate.gap;
  }
}
