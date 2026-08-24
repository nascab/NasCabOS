import 'package:NasCabOS/modules/base/components.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:get/get.dart';

class NotesEditorPane extends StatelessWidget {
  final NotesController controller;
  final bool compact;

  const NotesEditorPane({
    super.key,
    required this.controller,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final note = controller.currentNote.value;
      final showingTrash = controller.showingTrash.value;
      final saving = controller.savingNote.value;
      final loadingNoteDetail = controller.loadingNoteDetail.value;
      final editorVersion = controller.editorVersion.value;
      final showSaveFailureWarning = controller.showSaveFailureWarning.value;
      if (note == null) {
        return CustomNoData(
          text: showingTrash
              ? 'notes_select_deleted_note'.tr
              : 'notes_select_or_create_note'.tr,
          backgroundColor: Colors.transparent,
          imagePath: 'assets/icons/nodata_note.png',
        );
      }
      return Column(
        children: [
          Container(
            color: scheme.surface,
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: TextField(
                      controller: controller.titleController,
                      decoration: InputDecoration(
                        hintText: 'notes_untitled'.tr,
                        isCollapsed: true,
                        filled: true,
                        fillColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                if (!showingTrash)
                  Tooltip(
                    message: note.isPinned ? 'notes_unpin'.tr : 'notes_pin'.tr,
                    child: IconButton(
                      onPressed: () => controller.togglePinned(note),
                      color: scheme.onSurfaceVariant,
                      icon: Icon(
                        note.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showSaveFailureWarning)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.wifi_off_rounded,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'notes_save_connection_lost'.tr,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: CustomButton(
                      text: saving
                          ? 'editor_status_saving'.tr
                          : 'notes_manual_save'.tr,
                      onPressed: saving || !controller.canRetrySave
                          ? null
                          : controller.retryFailedSave,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            alignment: Alignment.centerLeft,
            color: scheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: QuillSimpleToolbar(
                    controller: controller.quillController,
                    config: controller.buildToolbarConfig(
                      compact: compact,
                      theme: theme,
                    ),
                  ),
                ),
                _buildToolbarMoreMenu(context),
              ],
            ),
          ),
          SizedBox(
            height: 1,
            child: saving || loadingNoteDetail
                ? const LinearProgressIndicator(minHeight: 1)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: scheme.surface,
                    child: KeyedSubtree(
                      key: ValueKey(editorVersion),
                      child: QuillEditor.basic(
                        controller: controller.quillController,
                        config: controller.buildEditorConfig(theme: theme),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildToolbarMoreMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (buttonContext) => Tooltip(
        message: 'more'.tr,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showToolbarMorePanel(buttonContext),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.more_horiz_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showToolbarMorePanel(BuildContext context) async {
    final buttonBox = context.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) return;

    const panelWidth = 324.0;
    const panelHeight = 196.0;
    final buttonBottomLeft = buttonBox.localToGlobal(
      Offset(0, buttonBox.size.height),
      ancestor: overlayBox,
    );
    final buttonBottomRight = buttonBox.localToGlobal(
      Offset(buttonBox.size.width, buttonBox.size.height),
      ancestor: overlayBox,
    );
    final maxLeft = overlayBox.size.width - panelWidth - 12;
    final maxTop = overlayBox.size.height - panelHeight - 12;
    final left = (buttonBottomRight.dx - panelWidth).clamp(12.0, maxLeft);
    final top = (buttonBottomLeft.dy + 8).clamp(12.0, maxTop);

    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'more'.tr,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, _, _) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              width: panelWidth,
              child: Material(
                color: scheme.surface,
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMoreActionRow(dialogContext, [
                        _EditorQuickAction(
                          'undo',
                          Icons.undo_rounded,
                          'notes_toolbar_undo'.tr,
                        ),
                        _EditorQuickAction(
                          'redo',
                          Icons.redo_rounded,
                          'notes_toolbar_redo'.tr,
                        ),
                        _EditorQuickAction(
                          'clear',
                          Icons.format_clear_rounded,
                          'notes_toolbar_clear'.tr,
                        ),
                        _EditorQuickAction(
                          'quote',
                          Icons.format_quote_rounded,
                          'notes_toolbar_quote'.tr,
                        ),
                        _EditorQuickAction(
                          'code',
                          Icons.code_rounded,
                          'notes_toolbar_code'.tr,
                        ),
                      ]),
                      const SizedBox(height: 8),
                      _buildMoreActionRow(dialogContext, [
                        _EditorQuickAction(
                          'bullet',
                          Icons.format_list_bulleted_rounded,
                          'notes_toolbar_list_bullet'.tr,
                        ),
                        _EditorQuickAction(
                          'number',
                          Icons.format_list_numbered_rounded,
                          'notes_toolbar_list_number'.tr,
                        ),
                        _EditorQuickAction(
                          'check',
                          Icons.checklist_rtl_rounded,
                          'notes_toolbar_list_check'.tr,
                        ),
                        _EditorQuickAction(
                          'image',
                          Icons.image_outlined,
                          'file_type_image'.tr,
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );

    if (action == null) return;
    await _handleToolbarMoreAction(action);
  }

  Widget _buildMoreActionRow(
    BuildContext context,
    List<_EditorQuickAction> actions,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: actions
          .map(
            (action) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Tooltip(
                  message: action.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(action.value),
                    child: Container(
                      height: 78,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            action.icon,
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _handleToolbarMoreAction(String value) async {
    if (value == 'image') {
      await controller.insertImageFromPicker();
      return;
    }
    if (value == 'undo') {
      controller.quillController.undo();
      return;
    }
    if (value == 'redo') {
      controller.quillController.redo();
      return;
    }
    if (value == 'bullet') {
      controller.quillController.formatSelection(Attribute.ul);
      return;
    }
    if (value == 'number') {
      controller.quillController.formatSelection(Attribute.ol);
      return;
    }
    if (value == 'check') {
      controller.quillController.formatSelection(Attribute.unchecked);
      return;
    }
    if (value == 'quote') {
      controller.quillController.formatSelection(Attribute.blockQuote);
      return;
    }
    if (value == 'code') {
      controller.quillController.formatSelection(Attribute.codeBlock);
      return;
    }
    if (value == 'clear') {
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.bold, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.italic, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.underline, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.strikeThrough, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.color, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.size, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.blockQuote, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.codeBlock, null),
      );
      controller.quillController.formatSelection(
        Attribute.clone(Attribute.list, null),
      );
    }
  }
}

class _EditorQuickAction {
  final String value;
  final IconData icon;
  final String label;

  const _EditorQuickAction(this.value, this.icon, this.label);
}
