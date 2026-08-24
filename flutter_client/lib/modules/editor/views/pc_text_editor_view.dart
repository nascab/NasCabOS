import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import '../../home/views/pc_components/pc_app_window.dart';
import '../controllers/editor_session_controller.dart';
import 'pc_components/editor_toolbar.dart';
import 'pc_components/editor_code_field.dart';

class PcTextEditorView extends StatelessWidget {
  const PcTextEditorView({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final instanceId = PcWindowScope.of(context)?.windowId ?? 'editor';
    final theme = Theme.of(context);

    return GetBuilder<EditorSessionController>(
      tag: instanceId,
      init: EditorSessionController(windowId: instanceId, filePath: filePath),
      builder: (controller) {
        return Scaffold(
          body: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: PcAppWindow.titleBarHeight),
              child: Column(
                children: [
                  EditorToolbar(controller: controller),
                  Expanded(
                    child: Container(
                      color: theme.colorScheme.surface,
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
                            wrap: false,
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
