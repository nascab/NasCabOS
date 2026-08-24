import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:NasCabOS/modules/notes/model/notes_models.dart';
import 'package:NasCabOS/modules/notes/view/parts/notes_view_utils.dart';
import 'package:NasCabOS/modules/base/components/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotesSidebar extends StatelessWidget {
  final NotesController controller;
  final bool desktop;

  const NotesSidebar({
    super.key,
    required this.controller,
    this.desktop = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Obx(() {
      final collapsed = desktop && controller.sidebarCollapsed.value;
      final selectedGroupId = controller.selectedGroupId.value;
      final showingTrash = controller.showingTrash.value;
      final sidebarColor = Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.03),
        scheme.surfaceContainerHighest,
      );
      return Container(
        color: sidebarColor,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 10 : 14,
                10,
                collapsed ? 10 : 14,
                8,
              ),
              child: Column(
                children: [
                  SizedBox(height: 30),
                  if (desktop)
                    Align(
                      alignment: collapsed
                          ? Alignment.center
                          : Alignment.centerLeft,
                      child: Tooltip(
                        message: collapsed
                            ? 'sidebar_expand'.tr
                            : 'sidebar_collapse'.tr,
                        child: IconButton(
                          onPressed: controller.toggleSidebarCollapsed,
                          icon: Icon(
                            collapsed
                                ? Icons.keyboard_double_arrow_right_rounded
                                : Icons.keyboard_double_arrow_left_rounded,
                          ),
                        ),
                      ),
                    ),
                  if (desktop) const SizedBox(height: 6),
                  if (collapsed)
                    _actionTile(
                      context,
                      title: 'notes_new'.tr,
                      icon: Icons.add_rounded,
                      onTap: controller.createNote,
                      collapsed: true,
                      collapsedUseIcon: true,
                    )
                  else
                    CustomButton(
                      text: 'notes_new'.tr,
                      onPressed: controller.createNote,
                      width: double.infinity,
                    ),
                  SizedBox(height: 10),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 10),
                child: Column(
                  children: [
                    _tile(
                      context,
                      title: 'all'.tr,
                      selected: selectedGroupId == 'all' && !showingTrash,
                      onTap: () => controller.changeGroup('all'),
                      collapsed: collapsed,
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: _buildReorderableGroups(
                        context,
                        collapsed,
                        selectedGroupId: selectedGroupId,
                        showingTrash: showingTrash,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
            Padding(
              padding: EdgeInsets.all(collapsed ? 8 : 14),
              child: collapsed
                  ? Tooltip(
                      message:
                          controller.notebook.value?.folderPath ??
                          'notes_switch_notebook'.tr,
                      child: IconButton(
                        onPressed: () => controller.pickNotebook(context),
                        icon: const Icon(Icons.sync_alt_rounded),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: 'notes_switch_notebook'.tr,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => controller.pickNotebook(context),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.sync_alt_rounded,
                                size: 18,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            message:
                                controller.notebook.value?.folderPath ??
                                'notes_switch_notebook'.tr,
                            child: Text(
                              controller.notebook.value?.folderPath ??
                                  controller.notebook.value?.name ??
                                  '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _createGroupTile(BuildContext context, bool collapsed) {
    return _actionTile(
      context,
      title: 'notes_new_group'.tr,
      icon: Icons.create_new_folder_outlined,
      onTap: controller.createGroup,
      collapsed: collapsed,
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    required bool collapsed,
    bool collapsedUseIcon = false,
  }) {
    return _tile(
      context,
      title: title,
      selected: false,
      onTap: onTap,
      collapsed: collapsed,
      icon: icon,
      collapsedUseIcon: collapsedUseIcon,
    );
  }

  Widget _buildReorderableGroups(
    BuildContext context,
    bool collapsed, {
    required String selectedGroupId,
    required bool showingTrash,
  }) {
    final customGroups = controller.groups
        .where((group) => group.id != 'all')
        .toList();
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.zero,
      itemCount: customGroups.length + 3,
      onReorder: (oldIndex, newIndex) async {
        if (oldIndex >= customGroups.length) return;
        final next = [...customGroups];
        if (newIndex > oldIndex) newIndex -= 1;
        if (newIndex > next.length) newIndex = next.length;
        final moved = next.removeAt(oldIndex);
        next.insert(newIndex, moved);
        await controller.reorderGroups(next);
      },
      itemBuilder: (context, index) {
        if (index == customGroups.length) {
          return Padding(
            key: const ValueKey('create-group-footer'),
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: _createGroupTile(context, collapsed),
          );
        }
        if (index == customGroups.length + 1) {
          return Padding(
            key: const ValueKey('trash-divider'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.8),
            ),
          );
        }
        if (index == customGroups.length + 2) {
          return Padding(
            key: const ValueKey('trash-tile'),
            padding: const EdgeInsets.only(bottom: 4),
            child: _tile(
              context,
              title: 'notes_recent_deleted'.tr,
              selected: showingTrash,
              onTap: () => controller.changeGroup('all', trash: true),
              collapsed: collapsed,
              icon: Icons.delete_outline_rounded,
              collapsedUseIcon: true,
            ),
          );
        }
        final group = customGroups[index];
        final selected = selectedGroupId == group.id && !showingTrash;
        return Padding(
          key: ValueKey(group.id),
          padding: const EdgeInsets.only(bottom: 4),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: GestureDetector(
              onSecondaryTapDown: (details) =>
                  _showGroupContextMenu(context, details.globalPosition, group),
              child: _tile(
                context,
                title: displayNotesGroupName(
                  groupId: group.id,
                  groupName: group.name,
                ),
                selected: selected,
                onTap: () => controller.changeGroup(group.id),
                collapsed: collapsed,
                trailing: collapsed
                    ? null
                    : Builder(
                        builder: (menuContext) => IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () async {
                            final box =
                                menuContext.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            final position = box.localToGlobal(
                              Offset(box.size.width - 4, box.size.height - 2),
                            );
                            await _showGroupContextMenu(
                              menuContext,
                              position,
                              group,
                            );
                          },
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: selected
                                ? Colors.white.withValues(alpha: 0.92)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required bool selected,
    required VoidCallback onTap,
    required bool collapsed,
    Widget? trailing,
    IconData icon = Icons.folder_open_outlined,
    bool collapsedUseIcon = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected ? scheme.primary : Colors.transparent;
    final fg = selected ? Colors.white : scheme.onSurface;
    final tileChild = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 8 : 10,
        vertical: 10,
      ),
      child: Row(
        children: [
          _buildTileLeading(
            context,
            title: title,
            collapsed: collapsed,
            selected: selected,
            fg: fg,
            icon: icon,
            collapsedUseIcon: collapsedUseIcon,
          ),
          if (!collapsed) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: title,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ],
      ),
    );
    return Tooltip(
      message: title,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: tileChild,
          ),
        ),
      ),
    );
  }

  Widget _buildTileLeading(
    BuildContext context, {
    required String title,
    required bool collapsed,
    required bool selected,
    required Color fg,
    required IconData icon,
    required bool collapsedUseIcon,
  }) {
    if (!collapsed) {
      return Icon(icon, size: 18, color: fg);
    }
    if (collapsedUseIcon) {
      return Icon(icon, size: 18, color: fg);
    }
    final scheme = Theme.of(context).colorScheme;
    final initial = _groupInitial(title);
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.18)
            : scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        initial,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _groupInitial(String title) {
    final value = title.trim();
    if (value.isEmpty) {
      return '?';
    }
    return value.characters.first.toUpperCase();
  }

  Future<void> _showGroupContextMenu(
    BuildContext context,
    Offset globalPosition,
    NotesGroup group,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(value: 'rename', child: Text('rename'.tr)),
        PopupMenuItem<String>(value: 'delete', child: Text('delete'.tr)),
      ],
    );
    if (selected == null || !context.mounted) return;
    if (selected == 'rename') {
      await controller.renameGroup(group);
      return;
    }
    if (selected == 'delete') {
      await controller.deleteGroup(group);
    }
  }
}
