import 'package:flutter/material.dart';

/// Shows the Pouse In-App Contextual Guide dialog explaining multi-touch gestures,
/// media controls, and shortcuts.
void showPouseGestureGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => const _GestureGuideSheet(),
  );
}

class _GestureGuideSheet extends StatelessWidget {
  const _GestureGuideSheet();

  Widget _buildGuideRow({
    required IconData icon,
    required String gesture,
    required String action,
    Color iconColor = Colors.cyanAccent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF282836),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gesture,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  action,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF181822),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF38384A), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.cyanAccent, size: 22),
              SizedBox(width: 10),
              Text(
                'Pouse Quick Guide & Gestures',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                  'TOUCHPAD GESTURES',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGuideRow(
                  icon: Icons.touch_app,
                  gesture: '1-Finger Tap / Drag',
                  action: 'Left click or move cursor',
                ),
                _buildGuideRow(
                  icon: Icons.mouse_outlined,
                  gesture: '2-Finger Tap',
                  action: 'Right click context menu',
                ),
                _buildGuideRow(
                  icon: Icons.swipe_vertical,
                  gesture: '2-Finger Drag',
                  action: 'Smooth vertical or horizontal scrolling',
                ),
                _buildGuideRow(
                  icon: Icons.swipe,
                  gesture: '2-Finger Swipe Left / Right',
                  action: 'Browser Back / Forward history',
                ),
                _buildGuideRow(
                  icon: Icons.vertical_align_top,
                  gesture: '3-Finger Swipe Up / Down',
                  action: 'Task View (Up) or Show Desktop (Down)',
                ),
                _buildGuideRow(
                  icon: Icons.swap_horiz,
                  gesture: '3-Finger Swipe Left / Right',
                  action: 'Switch active application (Alt+Tab)',
                ),
                _buildGuideRow(
                  icon: Icons.keyboard_double_arrow_right,
                  gesture: '4-Finger Swipe Left / Right',
                  action: 'Switch Windows Virtual Desktops',
                ),
                _buildGuideRow(
                  icon: Icons.pinch,
                  gesture: 'Pinch / Spread',
                  action: 'Zoom with Windows System Magnifier',
                ),
                const SizedBox(height: 14),
                const Text(
                  'UTILITY CONTROLS',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                _buildGuideRow(
                  icon: Icons.volume_up,
                  iconColor: Colors.amberAccent,
                  gesture: 'Volume & Mute',
                  action: 'Quick hardware volume control with mute toggle',
                ),
                _buildGuideRow(
                  icon: Icons.brightness_6,
                  iconColor: Colors.amberAccent,
                  gesture: 'Display Brightness',
                  action: 'Adjust primary monitor screen brightness',
                ),
                _buildGuideRow(
                  icon: Icons.search,
                  iconColor: Colors.lightGreenAccent,
                  gesture: 'Windows Search (Win+S)',
                  action: 'One-tap access to Windows global search bar',
                ),
                _buildGuideRow(
                  icon: Icons.desktop_windows,
                  iconColor: Colors.purpleAccent,
                  gesture: 'Remote Screen Mode',
                  action: 'Stream desktop display directly to your phone screen',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E3248),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
