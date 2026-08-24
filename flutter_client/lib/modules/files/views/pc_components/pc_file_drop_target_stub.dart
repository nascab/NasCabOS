import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:cross_file/cross_file.dart';

class PcFileDropTarget extends StatelessWidget {
  final Widget child;
  final Function(List<XFile> files) onDragDone;
  final VoidCallback? onDragEntered;
  final VoidCallback? onDragExited;

  const PcFileDropTarget({
    super.key,
    required this.child,
    required this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
