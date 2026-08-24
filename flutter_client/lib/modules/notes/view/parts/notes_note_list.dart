import 'dart:async';
import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:NasCabOS/modules/base/components/custom_expandable_search_bar.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:NasCabOS/utils/popup_menu_util.dart';
import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:NasCabOS/modules/notes/model/notes_models.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_view_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class NotesNoteList extends StatelessWidget {
  final NotesController controller;
  final bool showToolbar;
  final bool showSelectionState;
  final Future<void> Function(NotesNote note)? onNoteTap;

  const NotesNoteList({
    super.key,
    required this.controller,
    this.showToolbar = true,
    this.showSelectionState = true,
    this.onNoteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final visibleNotes = controller.visibleNotes;
      final filterActive =
          controller.tagColorFilter.value != NotesController.allTagFilterValue;
      final noteListColor = Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.02),
        scheme.surfaceContainerLow,
      );
      return Container(
        color: noteListColor,
        child: Column(
          children: [
            if (showToolbar)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomExpandableSearchBar(
                        hintText: 'search'.tr,
                        controller: controller.searchController,
                        defaultExpanded: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (ctx) => CustomBorderedIconButton(
                        icon: filterActive
                            ? Icons.label_rounded
                            : Icons.label_outline_rounded,
                        active: filterActive,
                        tooltip: 'notes_filter_all_tags'.tr,
                        onTap: () {
                          final renderBox = ctx.findRenderObject() as RenderBox;
                          final offset = renderBox.localToGlobal(Offset.zero);
                          final size = renderBox.size;
                          PopupMenuUtil.showBelowContent<String>(
                            context: ctx,
                            position: RelativeRect.fromLTRB(
                              offset.dx,
                              offset.dy + size.height + 4,
                              offset.dx + size.width,
                              offset.dy + size.height + 4,
                            ),
                            items: [
                              PopupMenuItem<String>(
                                value: NotesController.allTagFilterValue,
                                child: Text('notes_filter_all_tags'.tr),
                              ),
                              ...NotesController.presetColors.map((color) {
                                final parsed = parseNotesHexColor(color);
                                return PopupMenuItem<String>(
                                  value: color,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: parsed ?? Colors.transparent,
                                          border: Border.all(
                                            color: scheme.outlineVariant,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(_tagColorLabel(color)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ).then((value) {
                            if (value != null) {
                              controller.setTagColorFilter(value);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    CustomBorderedIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'refresh'.tr,
                      onTap: controller.refreshState,
                    ),
                  ],
                ),
              ),
            if (controller.loadingState.value)
              const LinearProgressIndicator(minHeight: 1),
            Expanded(
              child: visibleNotes.isEmpty
                  ? CustomNoData(
                      text: controller.notes.isNotEmpty && filterActive
                          ? 'notes_filter_empty'.tr
                          : controller.showingTrash.value
                          ? 'notes_trash_empty'.tr
                          : 'notes_list_empty'.tr,
                      backgroundColor: Colors.transparent,
                      imagePath: 'assets/icons/nodata_note.png',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                      itemCount: visibleNotes.length,
                      itemBuilder: (context, index) {
                        final note = visibleNotes[index];
                        final selected =
                            showSelectionState &&
                            controller.isNoteSelected(note.id);
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == visibleNotes.length - 1 ? 0 : 6,
                          ),
                          child: _item(context, note, selected),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _item(BuildContext context, NotesNote note, bool selected) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tagColor = parseNotesHexColor(note.tagColor);
    final selectedBg = selected
        ? scheme.primary
        : scheme.surfaceContainerLowest;
    final borderColor = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: 0.16);
    final primaryText = selected ? Colors.white : scheme.onSurface;
    final secondaryText = selected
        ? Colors.white.withValues(alpha: 0.84)
        : scheme.onSurfaceVariant;
    final previewText = selected
        ? Colors.white.withValues(alpha: 0.9)
        : scheme.onSurface.withValues(alpha: 0.78);
    final menuIconColor = selected
        ? Colors.white.withValues(alpha: 0.92)
        : scheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selectedBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _showNoteContextMenu(context, details.globalPosition, note),
          onLongPressStart: (details) =>
              _showNoteContextMenu(context, details.globalPosition, note),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              if (onNoteTap != null) {
                await onNoteTap!(note);
                return;
              }
              await controller.handleNoteTap(
                note,
                shiftPressed: _isShiftPressed,
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (tagColor != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tagColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (selected && controller.selectedNoteCount > 1) ...[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          displayNotesTitle(note.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryText,
                          ),
                        ),
                      ),
                      if (note.isPinned)
                        Tooltip(
                          message: 'notes_unpin'.tr,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => controller.togglePinned(note),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 14,
                                color: selected ? Colors.white : scheme.primary,
                              ),
                            ),
                          ),
                        ),
                      Builder(
                        builder: (buttonContext) => IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: () async {
                            final box =
                                buttonContext.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final pos = box.localToGlobal(
                              Offset(box.size.width - 8, box.size.height - 2),
                            );
                            await _showNoteContextMenu(
                              buttonContext,
                              pos,
                              note,
                            );
                          },
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 17,
                            color: menuIconColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatNotesTime(note.updateTime),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    note.preview.isEmpty
                        ? 'notes_editor_placeholder'.tr
                        : note.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: previewText,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.folder_open_rounded,
                        size: 12,
                        color: secondaryText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayNotesGroupName(
                            groupId: note.groupId,
                            groupName: note.groupName,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: selected
                                ? Colors.white.withValues(alpha: 0.84)
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: 0.92,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isShiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
  }

  Future<void> _showNoteContextMenu(
    BuildContext context,
    Offset globalPosition,
    NotesNote note,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dividerColor = scheme.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.55 : 0.9,
    );
    final batchSelected =
        controller.hasBatchSelection && controller.isNoteSelected(note.id);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (!note.isDeleted)
          PopupMenuItem<String>(
            value: 'pin',
            child: Text(note.isPinned ? 'notes_unpin'.tr : 'notes_pin'.tr),
          ),
        if (!note.isDeleted)
          PopupMenuItem<String>(
            value: 'tag_picker',
            child: Text('notes_tag'.tr),
          ),
        if (!note.isDeleted &&
            (batchSelected ||
                controller.groups.any((g) => g.id != note.groupId)))
          PopupMenuItem<String>(value: 'move_picker', child: Text('move'.tr)),
        if (!note.isDeleted)
          PopupMenuItem<String>(
            value: 'export_pdf',
            child: Text('notes_export_pdf'.tr),
          ),
        if (!note.isDeleted)
          PopupMenuItem<String>(
            value: 'export_markdown',
            child: Text('notes_export_markdown'.tr),
          ),
        if (!note.isDeleted)
          PopupMenuItem<String>(
            value: 'export_txt',
            child: Text('notes_export_txt'.tr),
          ),
        if (!note.isDeleted)
          PopupMenuItem<String>(
            enabled: false,
            height: 12,
            padding: EdgeInsets.zero,
            child: Divider(
              height: 1,
              thickness: 1,
              color: dividerColor.withValues(alpha: 0.2),
            ),
          ),
        if (note.isDeleted)
          PopupMenuItem<String>(
            value: 'restore',
            child: Text('notes_restore'.tr),
          ),
        PopupMenuItem<String>(
          value: note.isDeleted ? 'permanent_delete' : 'delete',
          child: Text(
            note.isDeleted
                ? 'notes_delete_forever'.tr
                : 'notes_move_to_trash'.tr,
          ),
        ),
      ],
    );
    if (selected == null) return;
    if (!context.mounted) return;
    if (selected == 'pin') {
      await controller.togglePinned(note);
      return;
    }
    if (selected == 'tag_picker') {
      await _showTagColorMenu(context, globalPosition, note);
      return;
    }
    if (selected == 'move_picker') {
      if (batchSelected) {
        await controller.moveSelectedNotes(context);
      } else {
        await _showMoveDialog(context, note);
      }
      return;
    }
    if (selected == 'export_pdf') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller.exportNote(note, 'pdf'));
      });
      return;
    }
    if (selected == 'export_markdown') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller.exportNote(note, 'markdown'));
      });
      return;
    }
    if (selected == 'export_txt') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller.exportNote(note, 'txt'));
      });
      return;
    }
    if (selected == 'delete') {
      if (batchSelected) {
        await controller.deleteSelectedNotes();
      } else {
        controller.currentNote.value = note;
        await controller.deleteCurrentNote();
      }
      return;
    }
    if (selected == 'restore') {
      if (batchSelected) {
        await controller.restoreSelectedNotes();
      } else {
        await controller.restoreNote(note);
      }
      return;
    }
    if (selected == 'permanent_delete') {
      if (batchSelected) {
        await controller.deleteSelectedNotes();
      } else {
        await controller.permanentlyDeleteNote(note);
      }
      return;
    }
  }

  Future<void> _showTagColorMenu(
    BuildContext context,
    Offset globalPosition,
    NotesNote note,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx + 8, globalPosition.dy + 8, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: NotesController.presetColors.map((color) {
        final parsed = parseNotesHexColor(color);
        return PopupMenuItem<String>(
          value: color,
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: parsed ?? Colors.transparent,
                  border: Border.all(color: scheme.outlineVariant),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(_tagColorLabel(color)),
            ],
          ),
        );
      }).toList(),
    );
    if (selected == null) return;
    await controller.setTagColor(note, selected);
  }

  Future<void> _showMoveDialog(BuildContext context, NotesNote note) async {
    final target = await controller.pickTargetGroup(
      context,
      excludedGroupId: note.groupId,
    );
    if (target == null) return;
    await controller.moveNoteTo(note.id, target.id);
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
