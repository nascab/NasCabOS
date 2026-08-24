import 'package:flutter/material.dart';

class MusicPlayCtrlFullScreenHeader extends StatelessWidget {
  final VoidCallback onClose;
  final double height;
  final double topPadding;

  const MusicPlayCtrlFullScreenHeader({
    super.key,
    required this.onClose,
    this.height = 96,
    this.topPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down, size: 28),
              ),
              const Expanded(child: SizedBox.shrink()),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
