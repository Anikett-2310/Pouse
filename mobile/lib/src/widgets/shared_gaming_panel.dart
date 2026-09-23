import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../websocket_service.dart';

enum GamingMode { arrow, wasd }

/// Shared Virtual Presentation / Gaming Key Panel.
///
/// Supports Arrow keys (Up, Down, Left, Right) and WASD keys with true
/// press-and-hold (KEY_DOWN / KEY_UP) semantics for presentation navigation and gaming.
/// Persists the selected mode (Arrow vs WASD) across sessions.
class SharedGamingPanel extends StatefulWidget {
  final WebSocketService wsService;

  const SharedGamingPanel({
    super.key,
    required this.wsService,
  });

  @override
  State<SharedGamingPanel> createState() => _SharedGamingPanelState();
}

class _SharedGamingPanelState extends State<SharedGamingPanel> {
  static const String prefGamingModeKey = 'pouse_gaming_mode';

  GamingMode _mode = GamingMode.arrow;
  final Set<String> _activeHeldKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _loadGamingModePreference();
  }

  Future<void> _loadGamingModePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(prefGamingModeKey);
      if (modeStr == 'wasd') {
        setState(() => _mode = GamingMode.wasd);
      } else {
        setState(() => _mode = GamingMode.arrow);
      }
    } catch (_) {}
  }

  Future<void> _saveGamingModePreference(GamingMode newMode) async {
    _releaseAllHeldKeys();
    setState(() => _mode = newMode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefGamingModeKey, newMode == GamingMode.wasd ? 'wasd' : 'arrow');
    } catch (_) {}
  }

  void _onKeyTouchDown(String key) {
    if (!_activeHeldKeys.contains(key)) {
      _activeHeldKeys.add(key);
      HapticFeedback.selectionClick();
      widget.wsService.sendKeyDown(key);
    }
  }

  void _onKeyTouchUp(String key) {
    if (_activeHeldKeys.contains(key)) {
      _activeHeldKeys.remove(key);
      widget.wsService.sendKeyUp(key);
    }
  }

  void _releaseAllHeldKeys() {
    for (final key in _activeHeldKeys.toList()) {
      widget.wsService.sendKeyUp(key);
    }
    _activeHeldKeys.clear();
  }

  @override
  void dispose() {
    _releaseAllHeldKeys();
    super.dispose();
  }

  Widget _buildKeyButton({
    required String label,
    required String keyProtocolName,
    required IconData icon,
  }) {
    final isPressed = _activeHeldKeys.contains(keyProtocolName);

    return Listener(
      onPointerDown: (_) => _onKeyTouchDown(keyProtocolName),
      onPointerUp: (_) => _onKeyTouchUp(keyProtocolName),
      onPointerCancel: (_) => _onKeyTouchUp(keyProtocolName),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 64,
        height: 54,
        decoration: BoxDecoration(
          color: isPressed
              ? Colors.blueAccent
              : const Color(0xFF2A2A36),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPressed ? Colors.cyanAccent : const Color(0xFF3F3F52),
            width: isPressed ? 2 : 1,
          ),
          boxShadow: isPressed
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isPressed ? Colors.white : Colors.white.withValues(alpha: 0.87),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isPressed ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArrow = _mode == GamingMode.arrow;

    final upKey = isArrow ? 'arrow_up' : 'w';
    final downKey = isArrow ? 'arrow_down' : 's';
    final leftKey = isArrow ? 'arrow_left' : 'a';
    final rightKey = isArrow ? 'arrow_right' : 'd';

    final upLabel = isArrow ? 'UP' : 'W';
    final downLabel = isArrow ? 'DOWN' : 'S';
    final leftLabel = isArrow ? 'LEFT' : 'A';
    final rightLabel = isArrow ? 'RIGHT' : 'D';

    final upIcon = isArrow ? Icons.keyboard_arrow_up : Icons.title;
    final downIcon = isArrow ? Icons.keyboard_arrow_down : Icons.south;
    final leftIcon = isArrow ? Icons.keyboard_arrow_left : Icons.west;
    final rightIcon = isArrow ? Icons.keyboard_arrow_right : Icons.east;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF16161C),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Switcher Header (Arrow Keys vs WASD Gaming)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => _saveGamingModePreference(GamingMode.arrow),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isArrow ? Colors.blueAccent : const Color(0xFF242430),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_calls,
                        size: 16,
                        color: isArrow ? Colors.white : Colors.white60,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Arrow Mode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isArrow ? Colors.white : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _saveGamingModePreference(GamingMode.wasd),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: !isArrow ? Colors.blueAccent : const Color(0xFF242430),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports,
                        size: 16,
                        color: !isArrow ? Colors.white : Colors.white60,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'WASD Mode',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: !isArrow ? Colors.white : Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Directional Pad Grid
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row (Up / W)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildKeyButton(
                    label: upLabel,
                    keyProtocolName: upKey,
                    icon: upIcon,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Bottom Row (Left / A, Down / S, Right / D)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildKeyButton(
                    label: leftLabel,
                    keyProtocolName: leftKey,
                    icon: leftIcon,
                  ),
                  const SizedBox(width: 6),
                  _buildKeyButton(
                    label: downLabel,
                    keyProtocolName: downKey,
                    icon: downIcon,
                  ),
                  const SizedBox(width: 6),
                  _buildKeyButton(
                    label: rightLabel,
                    keyProtocolName: rightKey,
                    icon: rightIcon,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
