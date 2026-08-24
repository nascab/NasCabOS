import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'device_utils.dart';
import '../core/config/nascab_endpoints.dart';

/// 官网隐私政策与用户协议 URL（与登录页一致，带当前界面语言参数）。
class LegalUrls {
  LegalUrls._();

  static const String privacyBase =
      '${NasCabEndpoints.websiteBaseUrl}/others/privacy.html';
  static const String agreementBase =
      '${NasCabEndpoints.websiteBaseUrl}/others/agreement.html';

  static String languageQuery() {
    final locale = Get.locale;
    if (locale == null) return 'en-US';
    final lang = locale.languageCode;
    final country = locale.countryCode?.isNotEmpty == true
        ? locale.countryCode!
        : '';
    return country.isNotEmpty ? '$lang-$country' : lang;
  }

  static String privacyUrl() => '$privacyBase?language=${languageQuery()}';

  static String agreementUrl() => '$agreementBase?language=${languageQuery()}';
}

/// 合规：Web / Windows 在系统浏览器新标签页打开；macOS / iOS / Android / Linux 在应用内 WebView 打开。
class LegalDocumentOpener {
  LegalDocumentOpener._();

  static Future<void> open(
    BuildContext context, {
    required String url,
    required String title,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (kIsWeb) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
      return;
    }
    if (DeviceUtils.isWindows) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
      return;
    }

    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _LegalWebViewPage(title: title, url: url),
      ),
    );
  }
}

class _LegalWebViewPage extends StatefulWidget {
  const _LegalWebViewPage({required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<_LegalWebViewPage> createState() => _LegalWebViewPageState();
}

class _LegalWebViewPageState extends State<_LegalWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = err.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_loading)
            Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            ),
          if (_error != null && !_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
