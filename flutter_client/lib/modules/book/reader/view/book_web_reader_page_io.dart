import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../utils/device_utils.dart';

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
  WebViewController? _controller;
  bool _loading = true;
  bool _openingExternally = false;
  int _progress = 0;
  String _errorText = '';
  bool _externalLaunchSucceeded = false;

  bool get _useExternalBrowser => DeviceUtils.isWindows;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[BookWebReaderPage] $message');
  }

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
    _log('open url=${widget.url}');
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (_useExternalBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openInExternalBrowser();
        }
      });
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            _log('nav ${req.url}');
            if (!mounted) return NavigationDecision.prevent;
            if (req.url.startsWith('nascab://close')) {
              Navigator.of(context).maybePop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p;
            });
          },
          onPageStarted: (url) {
            _log('started $url');
            if (!mounted) return;
            setState(() {
              _loading = true;
              _errorText = '';
              _progress = 0;
            });
          },
          onPageFinished: (url) {
            _log('finished $url');
            if (!mounted) return;
            setState(() {
              _loading = false;
            });
          },
          onWebResourceError: (err) {
            _log(
              'error code=${err.errorCode} type=${err.errorType} desc=${err.description} url=${err.url}',
            );
            if (!mounted) return;
            setState(() {
              _loading = false;
              _errorText = '${err.errorCode} ${err.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInExternalBrowser() async {
    if (_openingExternally) return;
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() {
        _loading = false;
        _errorText = 'Invalid URL';
      });
      return;
    }

    setState(() {
      _loading = true;
      _openingExternally = true;
      _errorText = '';
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (launched) {
        if (widget.closeAfterExternalLaunch) {
          Navigator.of(context).maybePop();
          return;
        }
        setState(() {
          _loading = false;
          _openingExternally = false;
          _externalLaunchSucceeded = true;
        });
        return;
      }
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = 'Failed to open in external browser';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _openingExternally = false;
        _errorText = error.toString();
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    widget.onDispose?.call().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_useExternalBrowser) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Opening in external browser...',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Text(
                    _errorText.isNotEmpty
                        ? _errorText
                        : (_externalLaunchSucceeded
                              ? 'Opened in external browser. Keep this page open while reading.'
                              : 'Opening in external browser...'),
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (_externalLaunchSucceeded) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _openInExternalBrowser,
                      child: const Text('Open Again'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      );
    }
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
            body: Stack(
              children: [
                WebViewWidget(controller: _controller!),
                if (_loading)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: LinearProgressIndicator(
                        value: _progress <= 0 || _progress >= 100
                            ? null
                            : (_progress / 100.0),
                        minHeight: 2,
                        color: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.surface.withValues(
                          alpha: 0.1,
                        ),
                      ),
                    ),
                  ),
                if (_errorText.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Material(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          _errorText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
