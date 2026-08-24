import 'package:flutter/material.dart';
import '../../../files/controllers/pc_file_explorer_controller.dart';

class UploadWebFolderDropTarget extends StatelessWidget {
  final Widget child;
  final PcFileExplorerController? ctrl;
  final Future<void> Function(dynamic dataTransfer)? onDropDataTransfer;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  const UploadWebFolderDropTarget({
    super.key,
    required this.child,
    this.ctrl,
    this.onDropDataTransfer,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
