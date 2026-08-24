import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_editor_pane.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_layout.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_mobile_view.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_notebook_chooser.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_note_list.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_sidebar.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_view_utils.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/utils/server_version_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotesView extends StatefulWidget {
  final bool appMode;

  const NotesView({super.key, this.appMode = false});

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  bool _lowVersionDialogShown = false;

  NotesController get controller => Get.isRegistered<NotesController>()
      ? Get.find<NotesController>()
      : Get.put(NotesController(), permanent: true);

  bool _isServerVersionTooLow() {
    return !ServerVersionUtil.isAtLeast(
      ApiController.instance.serverVersion,
      5,
    );
  }

  void _showLowServerVersionDialogOnce() {
    if (_lowVersionDialogShown) return;
    _lowVersionDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'server_version_too_low'.tr,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isServerVersionTooLow()) {
      _showLowServerVersionDialogOnce();
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Text('notes'.tr, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                CustomGlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'server_version_too_low'.tr,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    controller.ensureSessionFresh();
    if (widget.appMode) {
      return NotesMobileView(controller: controller);
    }
    return Obx(() {
      final hasNotebook = controller.notebookSelected.value;
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: hasNotebook
              ? _buildDesktopLayout(context)
              : NotesNotebookChooser(controller: controller),
        ),
      );
    });
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editorPaneColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.012),
      scheme.surface,
    );
    return Padding(
      padding: EdgeInsets.zero,
      child: Obx(() {
        final sidebarWidth = controller.sidebarCollapsed.value
            ? NotesLayout.sidebarCollapsedWidth
            : NotesLayout.sidebarExpandedWidth;
        final dividerColor = scheme.outlineVariant.withValues(alpha: 0.5);
        return Row(
          children: [
            SizedBox(
              width: sidebarWidth,
              child: NotesSidebar(controller: controller, desktop: true),
            ),
            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
            SizedBox(
              width: NotesLayout.noteListWidth,
              child: NotesNoteList(controller: NotesController.instance),
            ),
            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
            Expanded(
              child: Container(
                color: editorPaneColor,
                child: NotesEditorPane(controller: controller, compact: false),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: scheme.surfaceContainerLow,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _groupChip('all'.tr, 'all', false),
                      const SizedBox(width: 8),
                      ...controller.groups.map((group) {
                        if (group.id == 'all') return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _groupChip(
                            displayNotesGroupName(
                              groupId: group.id,
                              groupName: group.name,
                            ),
                            group.id,
                            false,
                          ),
                        );
                      }),
                      _groupChip('notes_recent_deleted'.tr, 'all', true),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: controller.createNote,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              IconButton(
                onPressed: () => controller.pickNotebook(context),
                icon: const Icon(Icons.folder_open_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 220,
                child: NotesNoteList(controller: NotesController.instance),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: NotesEditorPane(controller: controller, compact: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupChip(String title, String groupId, bool trash) {
    final selected =
        controller.showingTrash.value == trash &&
        controller.selectedGroupId.value == groupId;
    return ChoiceChip(
      label: Text(title),
      selected: selected,
      onSelected: (_) => controller.changeGroup(groupId, trash: trash),
    );
  }
}
