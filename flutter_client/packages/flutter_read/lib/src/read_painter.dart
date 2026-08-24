import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'read_data.dart';

class ReadPaint extends StatelessWidget {
  final PaintData data;
  final Widget? loadingWidget;

  const ReadPaint({super.key, required this.data, this.loadingWidget});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
        valueListenable: data.picture,
        builder: (BuildContext context, ui.Picture? value, Widget? child) {
          if (value != null) {
            return CustomPaint(
              painter: _Painter(value),
            );
          }
          return SizedBox(
            child: loadingWidget,
          );
        });
  }
}

class _Painter extends CustomPainter {
  final ui.Picture picture;

  _Painter(this.picture);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
