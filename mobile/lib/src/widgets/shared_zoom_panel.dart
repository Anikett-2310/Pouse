import 'package:flutter/material.dart';
import '../transports/pouse_transport.dart';

/// Zoom Utility Panel delivering application-level zoom shortcuts.
///
/// Sends Ctrl + + on [ + ] tap and Ctrl + - on [ − ] tap using the Pouse input pipeline.
class SharedZoomPanel extends StatelessWidget {
  final PouseTransport transport;

  const SharedZoomPanel({super.key, required this.transport});

  void _zoomIn() {
    transport.sendKeyDown('ctrl');
    transport.sendKeyDown('shift');
    transport.sendKeyPress('=');
    transport.sendKeyUp('shift');
    transport.sendKeyUp('ctrl');
  }

  void _zoomOut() {
    transport.sendKeyDown('ctrl');
    transport.sendKeyPress('-');
    transport.sendKeyUp('ctrl');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF16161D),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Zoom',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _zoomOut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A36),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '−',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 24),
              ElevatedButton(
                onPressed: _zoomIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A36),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '+',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
