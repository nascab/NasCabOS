import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../core/web/context_menu_stub.dart'
    if (dart.library.html) '../core/web/context_menu_web.dart';

class ContextMenuUtil {
  static void init() {
    disableDefaultContextMenu();
  }

  static ContextMenu buildMenu({
    required List<ContextMenuEntry> entries,
    Offset? position,
    EdgeInsets padding = const EdgeInsets.all(8.0),
    BoxDecoration? boxDecoration,
  }) {
    return ContextMenu(
      entries: entries,
      position: position,
      padding: padding,
      boxDecoration: boxDecoration,
    );
  }

  static Future<dynamic> showAtPosition(
    BuildContext context, {
    required List<ContextMenuEntry> entries,
    required Offset position,
    ValueChanged<dynamic>? onItemSelected,
  }) async {
    final menu = buildMenu(entries: entries, position: position);
    final selected = await menu.show(context);
    if (onItemSelected != null && selected != null) {
      onItemSelected(selected);
    }
    return selected;
  }

  static Widget region({
    required Widget child,
    required List<ContextMenuEntry> entries,
    ValueChanged<dynamic>? onItemSelected,
  }) {
    final menu = buildMenu(entries: entries);
    return ContextMenuRegion(
      contextMenu: menu,
      onItemSelected: onItemSelected,
      child: child,
    );
  }
}
