import 'package:flutter/material.dart';
import '../../../files/controllers/pc_file_explorer_controller.dart';

import 'upload_web_folder_drop_target_stub.dart'
    if (dart.library.html) 'upload_web_folder_drop_target.dart';

class UploadWebFolderDropTargetWrapper extends StatelessWidget {
  final Widget child;
  final PcFileExplorerController? ctrl;
  final Future<void> Function(dynamic dataTransfer)? onDropDataTransfer;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  const UploadWebFolderDropTargetWrapper({
    super.key,
    required this.child,
    this.ctrl,
    this.onDropDataTransfer,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  Widget build(BuildContext context) {
    return UploadWebFolderDropTarget(
      ctrl: ctrl,
      onDropDataTransfer: onDropDataTransfer,
      onDragEntered: onDragEntered,
      onDragExited: onDragExited,
      child: child,
    );
  }
}
