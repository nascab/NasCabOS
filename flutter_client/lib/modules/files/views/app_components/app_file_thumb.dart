import 'package:flutter/material.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../controllers/file_controller.dart';

class AppFileThumb extends StatelessWidget {
  const AppFileThumb({
    super.key,
    required this.ctrl,
    required this.name,
    required this.type,
    required this.path,
    required this.size,
    this.virtualType = '',
    this.isCustomPath = false,
  });

  final FileController ctrl;
  final String name;
  final String type;
  final String path;
  final double size;
  final String virtualType;
  final bool isCustomPath;

  @override
  Widget build(BuildContext context) {
    final String icon;
    if (virtualType == 'custom_add') {
      icon = 'assets/icons/file/folder_add.png';
    } else if (isCustomPath && type == 'dir') {
      icon = 'assets/icons/file/folder_custom.png';
    } else {
      icon = ctrl.iconFor(name, path, type);
    }
    final isNetwork = icon.startsWith('http://') || icon.startsWith('https://');

    Widget child;
    if (isNetwork) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomExtendedImage(
          imageUrl: icon,
          width: size,
          height: size,
          fit: BoxFit.cover,
          borderRadius: 10,
        ),
      );
    } else {
      child = Image.asset(icon, width: size, height: size, fit: BoxFit.contain);
    }

    if (type != 'video') return child;

    final overlaySize = size * 0.28;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Container(
          width: overlaySize,
          height: overlaySize,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(overlaySize / 2),
          ),
          child: Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: overlaySize * 0.78,
          ),
        ),
      ],
    );
  }
}
