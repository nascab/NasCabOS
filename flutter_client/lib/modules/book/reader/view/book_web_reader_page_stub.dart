import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BookWebReaderPage extends StatelessWidget {
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
            appBar: AppBar(title: Text(title)),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
