import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import 'pc_file_drop_target_stub.dart'
    if (dart.library.io) 'pc_file_drop_target_desktop.dart';

class PcFileDropTargetWrapper extends StatelessWidget {
  final Widget child;
  final Function(List<XFile> files) onDragDone;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  const PcFileDropTargetWrapper({
    super.key,
    required this.child,
    required this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  Widget build(BuildContext context) {
    return PcFileDropTarget(
      onDragDone: onDragDone,
      onDragEntered: onDragEntered,
      onDragExited: onDragExited,
      child: child,
    );
  }
}
