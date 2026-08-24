import 'package:NasCabOS/modules/notes/controller/notes_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotesNotebookChooser extends StatelessWidget {
  final NotesController controller;

  const NotesNotebookChooser({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missingPath = controller.notebook.value?.folderPath.trim() ?? '';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 0,
          color: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_rounded, size: 64, color: Color(0xFF4F6AF2)),
                const SizedBox(height: 18),
                Text(
                  'notes_notebook_choose_title'.tr,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'notes_notebook_choose_desc'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => controller.pickNotebook(context),
                  icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
                  label: Text(
                    'notes_choose_folder'.tr,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ),
                if (missingPath.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    '${'notes_original_path_missing'.tr}$missingPath',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
