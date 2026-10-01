import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../transports/pouse_transport.dart';

/// Reusable PC Controls panel widget providing dedicated Volume, Brightness,
/// and Windows Search controls, strictly separated from OS Actions.
class SharedPcControlsPanel extends StatelessWidget {
  final PouseTransport transport;

  const SharedPcControlsPanel({
    super.key,
    required this.transport,
  });

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color bg = const Color(0xFF23232C),
  }) {
    return Expanded(
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF131318),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 6),
              const Text(
                'PC CONTROLS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                'Windows System Controls',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // VOLUME SECTION
          Row(
            children: [
              _buildActionButton(
                icon: Icons.volume_down,
                label: 'Vol -',
                onTap: () => transport.sendVolumeDown(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.volume_off,
                label: 'Mute',
                color: Colors.orangeAccent,
                onTap: () => transport.sendVolumeMute(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.volume_up,
                label: 'Vol +',
                onTap: () => transport.sendVolumeUp(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // BRIGHTNESS & SEARCH SECTION
          Row(
            children: [
              _buildActionButton(
                icon: Icons.brightness_low,
                label: 'Bright -',
                color: Colors.amberAccent,
                onTap: () => transport.sendBrightnessDown(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.brightness_high,
                label: 'Bright +',
                color: Colors.amberAccent,
                onTap: () => transport.sendBrightnessUp(),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.search,
                label: 'Search (Win+S)',
                color: Colors.cyanAccent,
                onTap: () => transport.sendWindowsSearch(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
