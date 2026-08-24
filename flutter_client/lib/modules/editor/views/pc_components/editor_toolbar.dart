import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../controllers/editor_session_controller.dart';
import '../../service/editor_api_service.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.controller});

  final EditorSessionController controller;

  Future<void> _openSettingsDialog() async {
    final ctx = Get.context;
    if (ctx == null) return;

    var fontSize = controller.fontSize.value.toDouble();
    await Get.dialog<void>(
      StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('editor_settings'.tr),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${'editor_font_size'.tr}: ${fontSize.round()}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: fontSize,
                    min: 10,
                    max: 40,
                    divisions: 30,
                    label: fontSize.round().toString(),
                    onChanged: (v) => setState(() => fontSize = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await controller.resetConfig();
                  Get.back();
                },
                child: Text('editor_restore_defaults'.tr),
              ),
              TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
              FilledButton(
                onPressed: () async {
                  final cfg = EditorUserConfig(fontSize: fontSize.round());
                  await controller.saveConfig(cfg);
                  Get.back();
                },
                child: Text('ok'.tr),
              ),
            ],
          );
        },
      ),
      barrierDismissible: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: theme.iconTheme.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                Obx(() {
                  final text = controller.statusText.value.trim();
                  if (text.isEmpty) return const SizedBox.shrink();
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  );
                }),
              ],
            ),
          ),
          CustomBorderedIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'setting'.tr,
            onTap: () => _openSettingsDialog(),
          ),
          const SizedBox(width: 4),
          Obx(() {
            final writable = controller.canWrite.value;
            return CustomBorderedIconButton(
              icon: Icons.save_outlined,
              tooltip: 'save'.tr,
              onTap: writable ? controller.forceSave : null,
              enabled: writable,
            );
          }),
        ],
      ),
    );
  }
}
