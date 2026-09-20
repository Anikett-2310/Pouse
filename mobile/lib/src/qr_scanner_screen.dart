import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'pairing_payload.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanned = false;
  DateTime? _lastInvalidToastTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        final payload = PairingPayload.parse(rawValue);
        if (payload != null) {
          _isScanned = true;
          Navigator.of(context).pop(payload);
          return;
        } else {
          // Throttled feedback for invalid QR formats
          final now = DateTime.now();
          if (_lastInvalidToastTime == null ||
              now.difference(_lastInvalidToastTime!).inSeconds > 2) {
            _lastInvalidToastTime = now;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invalid QR code format. Please scan a Pouse PC QR code.'),
                  backgroundColor: Colors.orangeAccent,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Pouse PC QR'),
        backgroundColor: const Color(0xFF1E1E24),
      ),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blueAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Text(
              'Point your phone camera at the QR code displayed in the Pouse PC terminal',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
