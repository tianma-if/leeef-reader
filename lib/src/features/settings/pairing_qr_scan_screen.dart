import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/sync/trusted/pairing_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PairingQrScanScreen extends StatefulWidget {
  const PairingQrScanScreen({super.key});

  @override
  State<PairingQrScanScreen> createState() => _PairingQrScanScreenState();
}

class _PairingQrScanScreenState extends State<PairingQrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [BarcodeFormat.qrCode],
  );
  var _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      final invite = PairingInvite.tryParse(raw);
      if (invite == null) continue;
      _handled = true;
      Navigator.pop(context, invite);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.text('扫描配对二维码'))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.text('对准电脑上的二维码。两台设备需要连接同一个局域网。'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
