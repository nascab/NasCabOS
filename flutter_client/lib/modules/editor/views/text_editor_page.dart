import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import '../controllers/editor_session_controller.dart';
import 'pc_components/editor_code_field.dart';

class TextEditorPage extends StatelessWidget {
  const TextEditorPage({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instanceId = 'editor_page_${DateTime.now().microsecondsSinceEpoch}';

    return GetBuilder<EditorSessionController>(
      tag: instanceId,
      init: EditorSessionController(windowId: instanceId, filePath: filePath),
      builder: (controller) {
        return Scaffold(
          appBar: AppBar(
            title: Text(controller.fileName),
            actions: [
              Obx(() {
                final writable = controller.canWrite.value;
                return TextButton(
                  onPressed: writable ? controller.forceSave : null,
                  child: Text('save'.tr),
                );
              }),
            ],
          ),
          body: Column(
            children: [
              Obx(() {
                final text = controller.statusText.value.trim();
                if (text.isEmpty) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    text,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                  ),
                );
              }),
              Expanded(
                child: Obx(() {
                  final styles = theme.brightness == Brightness.dark
                      ? monokaiSublimeTheme
                      : githubTheme;
                  final readOnly = !controller.canWrite.value;
                  final fontSize = controller.fontSize.value.toDouble();
                  return CodeTheme(
                    data: CodeThemeData(styles: styles),
                    child: EditorCodeField(
                      controller: controller.codeController,
                      readOnly: readOnly,
                      expands: true,
                      wrap: true,
                      lineNumbers: true,
                      cursorColor: theme.colorScheme.primary,
                      textStyle: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: fontSize,
                        height: 1.45,
                        color: theme.colorScheme.onSurface,
                      ),
                      padding: const EdgeInsets.all(12),
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
