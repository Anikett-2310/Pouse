import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../transports/pouse_transport.dart';

/// Shared OS Actions Panel providing 1-tap access to Windows OS actions:
/// - Windows Navigation: Task View, Show Desktop, Taskbar Apps, Previous/Next App, Prev/Next Desktop.
class SharedOsActionsPanel extends StatelessWidget {
  final PouseTransport transport;

  const SharedOsActionsPanel({
    super.key,
    required this.transport,
  });

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.cyanAccent,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF242430),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF38384A)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF16161C),
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Windows Navigation (Task View, Show Desktop, Taskbar Apps)
            Row(
              children: [
                _buildActionButton(
                  label: 'Task View',
                  icon: Icons.window_outlined,
                  onTap: () => transport.sendThreeFingerUp(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  label: 'Show Desktop',
                  icon: Icons.desktop_windows_outlined,
                  onTap: () => transport.sendThreeFingerDown(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  label: 'Taskbar Apps',
                  icon: Icons.view_sidebar_outlined,
                  iconColor: Colors.tealAccent,
                  onTap: () => transport.sendTaskbarApps(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 2: App Navigation
            Row(
              children: [
                _buildActionButton(
                  label: 'Previous App',
                  icon: Icons.arrow_back_outlined,
                  onTap: () => transport.sendThreeFingerLeft(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  label: 'Next App',
                  icon: Icons.arrow_forward_outlined,
                  onTap: () => transport.sendThreeFingerRight(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 3: Virtual Desktops
            Row(
              children: [
                _buildActionButton(
                  label: 'Prev Desktop',
                  icon: Icons.fast_rewind_outlined,
                  onTap: () => transport.sendFourFingerLeft(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  label: 'Next Desktop',
                  icon: Icons.fast_forward_outlined,
                  onTap: () => transport.sendFourFingerRight(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
