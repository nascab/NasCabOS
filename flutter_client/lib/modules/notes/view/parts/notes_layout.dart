import 'package:flutter/material.dart';

class NotesLayout {
  static const double sidebarExpandedWidth = 188;
  static const double sidebarCollapsedWidth = 68;
  static const double noteListWidth = 268;
  static const double minDesktopWidth = 1080;
  static const double minDesktopHeight = 640;
}

Color notesDividerColor(ColorScheme scheme) {
  return scheme.outlineVariant.withValues(alpha: 0.45);
}
