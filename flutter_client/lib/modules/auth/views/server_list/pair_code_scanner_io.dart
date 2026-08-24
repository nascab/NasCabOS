import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import '../../../../core/theme/dark_theme.dart';

Future<String?> scanPairCodeQr(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const _PairCodeQrScannerPage()),
  );
}

class _PairCodeQrScannerPage extends StatefulWidget {
  const _PairCodeQrScannerPage();

  @override
  State<_PairCodeQrScannerPage> createState() => _PairCodeQrScannerPageState();
}

class _PairCodeQrScannerPageState extends State<_PairCodeQrScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'pair_code_qr');
  QRViewController? _controller;
  var _returned = false;

  @override
  void reassemble() {
    super.reassemble();
    _controller?.pauseCamera();
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = Navigator.of(context);
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Text('server_pair_code_scan_qr'.tr),
              leading: IconButton(
                onPressed: () => nav.pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            body: QRView(
              key: qrKey,
              onQRViewCreated: (controller) {
                _controller = controller;
                controller.scannedDataStream.listen((scanData) {
                  if (_returned) return;
                  final raw = (scanData.code ?? '').trim();
                  if (raw.isEmpty) return;
                  if (!mounted) return;
                  _returned = true;
                  nav.pop(raw);
                });
              },
            ),
          );
        },
      ),
    );
  }
}
