import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import '../../base/components/custom_icon_button.dart';

class PanoramaGalleryPage extends StatefulWidget {
  const PanoramaGalleryPage({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<PanoramaGalleryPage> createState() => _PanoramaGalleryPageState();
}

class _PanoramaGalleryPageState extends State<PanoramaGalleryPage> {
  final FocusNode _focusNode = FocusNode();

  void _exit() {
    Navigator.of(context).maybePop();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _exit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: PanoramaViewer(
                child: Image.network(
                  widget.imageUrl,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                  child: CustomIconButton(
                    icon: Icons.close,
                    onPressed: _exit,
                    iconColor: Colors.white,
                    iconSize: 24,
                    buttonSize: 44,
                    tooltip: 'close'.tr,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
