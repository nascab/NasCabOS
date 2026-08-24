import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:NasCabOS/modules/notes/model/notes_models.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_editor_pane.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_note_list.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_notebook_chooser.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_view_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

enum _NotesMobileTab { notes, trash, settings }

class NotesMobileView extends StatefulWidget {
  final NotesController controller;

  const NotesMobileView({super.key, required this.controller});

  @override
  State<NotesMobileView> createState() => _NotesMobileViewState();
}

class _NotesMobileViewState extends State<NotesMobileView> {
  _NotesMobileTab _tab = _NotesMobileTab.notes;
  String _lastNormalGroupId = 'all';

  NotesController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!controller.showingTrash.value) {
      _lastNormalGroupId = controller.selectedGroupId.value;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await controller.changeGroup(_lastNormalGroupId);
    });
  }

  Future<void> _selectBottomTab(_NotesMobileTab next) async {
    if (_tab == next) return;
    setState(() => _tab = next);
    if (next == _NotesMobileTab.notes) {
      await controller.changeGroup(_lastNormalGroupId);
      return;
    }
    if (next == _NotesMobileTab.trash) {
      if (!controller.showingTrash.value) {
        _lastNormalGroupId = controller.selectedGroupId.value;
      }
      await controller.changeGroup('all', trash: true);
    }
  }

  Future<void> _selectGroup(String groupId) async {
    _lastNormalGroupId = groupId;
    await controller.changeGroup(groupId);
  }

  Future<void> _handleCreateNote() async {
    await controller.createNote();
    if (!mounted || controller.currentNote.value == null) return;
    await _openCurrentNoteEditor();
  }

  Future<void> _handleOpenNote(NotesNote note) async {
    await controller.selectNote(note.id);
    if (!mounted || controller.currentNote.value == null) return;
    await _openCurrentNoteEditor();
  }

  Future<void> _openCurrentNoteEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _NotesMobileEditorPage(controller: controller),
      ),
    );
  }

  Future<void> _showTagFilterSheet() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(
                  controller.tagColorFilter.value ==
                          NotesController.allTagFilterValue
                      ? Icons.check_circle_rounded
                      : Icons.label_outline_rounded,
                  color: scheme.primary,
                ),
                title: Text('notes_filter_all_tags'.tr),
                onTap: () {
                  controller.clearTagColorFilter();
                  Navigator.of(sheetContext).pop();
                },
              ),
              ...NotesController.presetColors.map((color) {
                final parsed = parseNotesHexColor(color);
                final selected = controller.tagColorFilter.value == color;
                return ListTile(
                  leading: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: parsed ?? Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 12, color: scheme.onPrimary)
                        : null,
                  ),
                  title: Text(_tagColorLabel(color)),
                  onTap: () {
                    controller.setTagColorFilter(color);
                    Navigator.of(sheetContext).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    return Obx(() {
      if (!controller.showingTrash.value) {
        _lastNormalGroupId = controller.selectedGroupId.value;
      }
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: barColor,
            statusBarIconBrightness: theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: theme.brightness,
            systemNavigationBarColor: barColor,
            systemNavigationBarIconBrightness:
                theme.brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarDividerColor: barColor,
          ),
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(child: SafeArea(top: false, child: _buildBody(context))),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab.index,
          onTap: (index) => _selectBottomTab(_NotesMobileTab.values[index]),
          selectedItemColor: theme.colorScheme.primary,
          unselectedItemColor: theme.colorScheme.onSurfaceVariant,
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.note_alt_outlined),
              label: 'app_note'.tr,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.delete_outline_rounded),
              label: 'notes_recent_deleted'.tr,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              label: 'setting'.tr,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final barColor =
        customColors?.oprationBarBgColor ?? theme.colorScheme.surface;
    final showSearch = _tab != _NotesMobileTab.settings;
    return Material(
      color: barColor,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    CustomBorderedIconButton(
                      icon: Icons.home_outlined,
                      tooltip: 'home'.tr,
                      onTap: () => Get.back(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: showSearch
                          ? CustomExpandableSearchBar(
                              hintText: 'search'.tr,
                              controller: controller.searchController,
                              defaultExpanded: true,
                            )
                          : Text(
                              'setting'.tr,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                    if (_tab == _NotesMobileTab.notes &&
                        controller.notebookSelected.value) ...[
                      const SizedBox(width: 8),
                      CustomBorderedIconButton(
                        icon:
                            controller.tagColorFilter.value !=
                                NotesController.allTagFilterValue
                            ? Icons.label_rounded
                            : Icons.label_outline_rounded,
                        tooltip: 'notes_filter_tag'.tr,
                        onTap: _showTagFilterSheet,
                        active:
                            controller.tagColorFilter.value !=
                            NotesController.allTagFilterValue,
                      ),
                      const SizedBox(width: 8),
                      CustomBorderedIconButton(
                        icon: Icons.add,
                        tooltip: 'notes_new'.tr,
                        onTap: _handleCreateNote,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_tab == _NotesMobileTab.notes &&
                controller.notebookSelected.value)
              _buildNotesActionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesActionBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildGroupChip(context, 'all'.tr, 'all'),
            const SizedBox(width: 8),
            ...controller.groups.where((group) => group.id != 'all').map((
              group,
            ) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildGroupChip(
                  context,
                  displayNotesGroupName(
                    groupId: group.id,
                    groupName: group.name,
                  ),
                  group.id,
                ),
              );
            }),
            _buildActionChip(
              context,
              icon: Icons.create_new_folder_outlined,
              label: 'notes_new_group'.tr,
              onTap: controller.createGroup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupChip(BuildContext context, String title, String groupId) {
    final selected =
        !controller.showingTrash.value &&
        controller.selectedGroupId.value == groupId;
    return ChoiceChip(
      label: Text(title),
      selected: selected,
      onSelected: (_) => _selectGroup(groupId),
    );
  }

  Widget _buildActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      backgroundColor: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest,
      label: Text(label),
      onPressed: onTap,
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_tab == _NotesMobileTab.settings) {
      return _buildSettingsBody(context);
    }
    if (!controller.notebookSelected.value) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NotesNotebookChooser(controller: controller),
        ),
      );
    }
    if (_tab == _NotesMobileTab.trash) {
      return NotesNoteList(
        controller: controller,
        showToolbar: false,
        showSelectionState: false,
        onNoteTap: _handleOpenNote,
      );
    }
    return NotesNoteList(
      controller: controller,
      showToolbar: false,
      showSelectionState: false,
      onNoteTap: _handleOpenNote,
    );
  }

  Widget _buildSettingsBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notebook = controller.notebook.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notebook?.name.isNotEmpty == true
                    ? notebook!.name
                    : 'app_note'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'path'.tr,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                notebook?.folderPath.isNotEmpty == true
                    ? notebook!.folderPath
                    : 'notes_notebook_choose_desc'.tr,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => controller.pickNotebook(context),
                style: FilledButton.styleFrom(
                  foregroundColor: Colors.white,
                  iconColor: Colors.white,
                ),
                icon: const Icon(Icons.folder_open_rounded),
                label: Text('notes_switch_notebook'.tr),
              ),
            ],
          ),
        ),
        if (controller.notebookSelected.value && notebook != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.note_alt_outlined,
                    label: 'app_note'.tr,
                    value: '${notebook.noteCount}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    icon: Icons.delete_outline_rounded,
                    label: 'notes_recent_deleted'.tr,
                    value: '${notebook.deletedCount}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _tagColorLabel(String color) {
    switch (color) {
      case '':
        return 'notes_no_tag'.tr;
      case '#EF4444':
        return 'notes_tag_color_red'.tr;
      case '#F59E0B':
        return 'notes_tag_color_orange'.tr;
      case '#10B981':
        return 'notes_tag_color_green'.tr;
      case '#3B82F6':
        return 'notes_tag_color_blue'.tr;
      case '#8B5CF6':
        return 'notes_tag_color_purple'.tr;
      case '#EC4899':
        return 'notes_tag_color_pink'.tr;
      default:
        return color;
    }
  }
}

class _NotesMobileEditorPage extends StatelessWidget {
  final NotesController controller;

  const _NotesMobileEditorPage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final note = controller.currentNote.value;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            note == null ? 'notes'.tr : displayNotesTitle(note.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (controller.savingNote.value)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (note != null)
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    await controller.deleteCurrentNote();
                    if (context.mounted) Navigator.of(context).maybePop();
                    return;
                  }
                  if (value == 'restore') {
                    await controller.restoreNote(note);
                    if (context.mounted) Navigator.of(context).maybePop();
                    return;
                  }
                  if (value == 'permanent_delete') {
                    await controller.permanentlyDeleteNote(note);
                    if (context.mounted) Navigator.of(context).maybePop();
                    return;
                  }
                  if (value == 'export_pdf') {
                    await controller.exportNote(note, 'pdf');
                    return;
                  }
                  if (value == 'export_markdown') {
                    await controller.exportNote(note, 'markdown');
                    return;
                  }
                  if (value == 'export_txt') {
                    await controller.exportNote(note, 'txt');
                  }
                },
                itemBuilder: (menuContext) {
                  if (controller.showingTrash.value) {
                    return [
                      PopupMenuItem<String>(
                        value: 'restore',
                        child: Text('restore'.tr),
                      ),
                      PopupMenuItem<String>(
                        value: 'permanent_delete',
                        child: Text('notes_delete_forever'.tr),
                      ),
                    ];
                  }
                  return [
                    PopupMenuItem<String>(
                      value: 'export_pdf',
                      child: Text('notes_export_pdf'.tr),
                    ),
                    PopupMenuItem<String>(
                      value: 'export_markdown',
                      child: Text('notes_export_markdown'.tr),
                    ),
                    PopupMenuItem<String>(
                      value: 'export_txt',
                      child: Text('notes_export_txt'.tr),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('delete'.tr),
                    ),
                  ];
                },
              ),
          ],
        ),
        body: NotesEditorPane(controller: controller, compact: true),
      );
    });
  }
}
