import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../websocket_service.dart';

/// Shared OS Actions Panel providing 1-tap fallback access to Windows OS actions:
/// Task View, Show Desktop, Previous App, Next App, Previous Virtual Desktop, and Next Virtual Desktop.
class SharedOsActionsPanel extends StatelessWidget {
  final WebSocketService wsService;

  const SharedOsActionsPanel({
    super.key,
    required this.wsService,
  });

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF242430),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF38384A)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.cyanAccent, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF16161C),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildActionButton(
                label: 'Task View',
                icon: Icons.window_outlined,
                onTap: () => wsService.sendThreeFingerUp(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                label: 'Show Desktop',
                icon: Icons.desktop_windows_outlined,
                onTap: () => wsService.sendThreeFingerDown(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildActionButton(
                label: 'Previous App',
                icon: Icons.arrow_back_outlined,
                onTap: () => wsService.sendThreeFingerLeft(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                label: 'Next App',
                icon: Icons.arrow_forward_outlined,
                onTap: () => wsService.sendThreeFingerRight(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildActionButton(
                label: 'Prev Desktop',
                icon: Icons.fast_rewind_outlined,
                onTap: () => wsService.sendFourFingerLeft(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                label: 'Next Desktop',
                icon: Icons.fast_forward_outlined,
                onTap: () => wsService.sendFourFingerRight(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
