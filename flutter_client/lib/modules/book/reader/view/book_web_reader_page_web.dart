import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

class BookWebReaderPage extends StatefulWidget {
  final String url;
  final String title;
  final Future<void> Function()? onDispose;
  final bool closeAfterExternalLaunch;

  const BookWebReaderPage({
    super.key,
    required this.url,
    required this.title,
    this.onDispose,
    this.closeAfterExternalLaunch = true,
  });

  @override
  State<BookWebReaderPage> createState() => _BookWebReaderPageState();
}

class _BookWebReaderPageState extends State<BookWebReaderPage> {
  late final String _viewType;

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    Navigator.of(context).maybePop();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _viewType = 'web_preview_${DateTime.now().microsecondsSinceEpoch}';
    final url = widget.url;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'clipboard-read; clipboard-write';
      return iframe;
    });
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    widget.onDispose?.call().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                Navigator.of(context).maybePop();
                return null;
              },
            ),
          },
          child: Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: HtmlElementView(viewType: _viewType),
          ),
        ),
      ),
    );
  }
}
