import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'package:NasCabOS/core/api/http_client_factory.dart'
    if (dart.library.html) 'package:NasCabOS/core/api/http_client_factory_web.dart'
    if (dart.library.io) 'package:NasCabOS/core/api/http_client_factory_io.dart';
import 'package:NasCabOS/utils/toast_util.dart';

String _formatBytes(int n) {
  if (n < 1024) return '$n B';
  final kb = n / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(2)} MB';
}

/// Web P2P：流式拉取 PDF 到内存，带进度与取消（关闭 [http.Client] 以中断请求）。
///
/// [hintTotalBytes]：响应无 Content-Length 时用于估算进度条（如文件列表里的 size）。
Future<Uint8List?> showWebP2pPdfLoadDialog(
  String fetchUrl, {
  int? hintTotalBytes,
}) {
  final hint = hintTotalBytes != null && hintTotalBytes > 0
      ? hintTotalBytes
      : null;
  return Get.dialog<Uint8List?>(
    _WebP2pPdfLoadDialog(fetchUrl: fetchUrl.trim(), hintTotalBytes: hint),
    barrierDismissible: false,
  );
}

class _WebP2pPdfLoadDialog extends StatefulWidget {
  const _WebP2pPdfLoadDialog({
    required this.fetchUrl,
    this.hintTotalBytes,
  });

  final String fetchUrl;
  final int? hintTotalBytes;

  @override
  State<_WebP2pPdfLoadDialog> createState() => _WebP2pPdfLoadDialogState();
}

class _WebP2pPdfLoadDialogState extends State<_WebP2pPdfLoadDialog> {
  http.Client? _client;
  bool _cancelled = false;
  bool _completed = false;
  int _received = 0;
  int? _total;

  void _detachAndCloseClient() {
    final c = _client;
    _client = null;
    if (c == null) return;
    try {
      c.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    _detachAndCloseClient();
    super.dispose();
  }

  void _finish(Uint8List? result) {
    if (_completed) return;
    _completed = true;
    if (mounted) {
      Get.back(result: result);
    }
  }

  Future<void> _onCancel() async {
    if (_completed) return;
    _cancelled = true;
    _detachAndCloseClient();
    _finish(null);
  }

  Future<void> _run() async {
    final url = widget.fetchUrl.trim();
    if (url.isEmpty) {
      ToastUtil.show('operation_failed'.tr);
      _finish(null);
      return;
    }

    final client = createHttpClient();
    _client = client;
    try {
      final request = http.Request('GET', Uri.parse(url));
      final streamed = await client.send(request).timeout(
            const Duration(minutes: 3),
          );

      if (_cancelled) {
        await streamed.stream.drain();
        return;
      }

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        ToastUtil.show('operation_failed'.tr);
        _finish(null);
        return;
      }

      final len = streamed.contentLength;
      final total = (len != null && len > 0)
          ? len
          : (widget.hintTotalBytes != null && widget.hintTotalBytes! > 0
              ? widget.hintTotalBytes
              : null);
      if (mounted) {
        setState(() => _total = total);
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        if (_cancelled) break;
        builder.add(chunk);
        _received = builder.length;
        if (mounted) setState(() {});
      }

      if (_cancelled) {
        _finish(null);
        return;
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        ToastUtil.show('operation_failed'.tr);
        _finish(null);
        return;
      }
      _finish(bytes);
    } catch (_) {
      if (!_cancelled) {
        ToastUtil.show('operation_failed'.tr);
      }
      _finish(null);
    } finally {
      if (identical(_client, client)) {
        _detachAndCloseClient();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;
    final progress = (total != null && total > 0)
        ? (_received / total).clamp(0.0, 1.0)
        : null;

    final detail = (total != null && total > 0)
        ? '${_formatBytes(_received)} / ${_formatBytes(total)}'
        : _received > 0
            ? _formatBytes(_received)
            : '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_onCancel());
        }
      },
      child: AlertDialog(
        title: Text('pdf_viewer_web_p2p_downloading'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (progress != null)
              LinearProgressIndicator(value: progress)
            else
              const LinearProgressIndicator(),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _completed ? null : () => unawaited(_onCancel()),
            child: Text('cancel'.tr),
          ),
        ],
      ),
    );
  }
}
