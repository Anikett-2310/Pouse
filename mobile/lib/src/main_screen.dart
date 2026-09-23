import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mouse_mode_manager.dart';
import 'pairing_payload.dart';
import 'qr_scanner_screen.dart';
import 'sources/motion_source.dart';
import 'sources/touchpad_source.dart';
import 'views/motion_view.dart';
import 'views/touchpad_view.dart';
import 'websocket_service.dart';

/// The Unified App Shell for Pouse V1.1.
///
/// Houses the persistent Connection Bar (QR scanner, manual IP input, Connect toggle,
/// status badge), the Mode Selector header, and renders the active mode view
/// driven by [MouseModeManager] without disrupting the active connection.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final WebSocketService _wsService = WebSocketService();
  final MouseModeManager _modeManager = MouseModeManager();
  final TextEditingController _ipController = TextEditingController();
  late final MotionSource _motionSource;

  @override
  void initState() {
    super.initState();
    _motionSource = MotionSource(_wsService);
    _loadSavedIp();
    _wsService.errorNotifier.addListener(_onErrorChanged);

    // Register InputSources for Touchpad (V1) and Motion (V2)
    _modeManager.registerSource(TouchpadSource(_wsService));
    _modeManager.registerSource(_motionSource);
  }

  void _onErrorChanged() {
    final error = _wsService.errorNotifier.value;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('pouse_pc_ip') ?? '';
    _ipController.text = savedIp;
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pouse_pc_ip', ip);
  }

  Future<void> _openQrScanner() async {
    final payload = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (payload != null && mounted) {
      _ipController.text = payload.host;
      await _saveIp(payload.host);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paired with ${payload.name} (${payload.host}:${payload.port})'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      _wsService.connect(payload.host, port: payload.port);
    }
  }

  void _toggleConnection() {
    if (_wsService.status == ConnectionStatus.connected) {
      _wsService.disconnect();
    } else {
      final ip = _ipController.text.trim();
      if (ip.isNotEmpty) {
        _saveIp(ip);
        _wsService.connect(ip);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your PC IP address')),
        );
      }
    }
  }

  @override
  void dispose() {
    _wsService.errorNotifier.removeListener(_onErrorChanged);
    _wsService.disconnect();
    _ipController.dispose();
    _modeManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.mouse, color: Colors.blueAccent),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: _modeManager,
              builder: (context, _) {
                final source = _modeManager.activeSource;
                final modeName = source?.displayName ?? 'Touchpad';
                return Text(
                  'Pouse — $modeName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                );
              },
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E24),
        elevation: 0,
        actions: [
          ValueListenableBuilder<ConnectionStatus>(
            valueListenable: _wsService.statusNotifier,
            builder: (context, status, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Chip(
                  avatar: CircleAvatar(
                    radius: 5,
                    backgroundColor: _getStatusColor(status),
                  ),
                  label: Text(
                    status.name.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: const Color(0xFF2A2A36),
                  side: BorderSide.none,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1E1E24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'PC IP Address (e.g. 192.168.1.100)',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF2A2A36),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.wifi, color: Colors.blueAccent, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent, size: 20),
                        onPressed: _openQrScanner,
                        tooltip: 'Scan PC QR Code',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder<ConnectionStatus>(
                  valueListenable: _wsService.statusNotifier,
                  builder: (context, status, child) {
                    final isConnected = status == ConnectionStatus.connected;
                    final isConnecting = status == ConnectionStatus.connecting;

                    return ElevatedButton(
                      onPressed: isConnecting ? null : _toggleConnection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? Colors.redAccent : Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isConnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              isConnected ? 'Disconnect' : 'Connect',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Mode Selector Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF16161B),
            child: ListenableBuilder(
              listenable: _modeManager,
              builder: (context, _) {
                final currentMode = _modeManager.currentMode;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildModeChip(
                        mode: MouseMode.touchpad,
                        label: 'Touchpad',
                        badge: null,
                        icon: Icons.touch_app,
                        isSelected: currentMode == MouseMode.touchpad,
                        isEnabled: true,
                        onTap: () => _modeManager.selectMode(MouseMode.touchpad),
                      ),
                      const SizedBox(width: 8),
                      _buildModeChip(
                        mode: MouseMode.motion,
                        label: 'Motion',
                        badge: null,
                        icon: Icons.screen_rotation,
                        isSelected: currentMode == MouseMode.motion,
                        isEnabled: true,
                        onTap: () => _modeManager.selectMode(MouseMode.motion),
                      ),
                      const SizedBox(width: 8),
                      _buildModeChip(
                        mode: MouseMode.optical,
                        label: 'Optical',
                        badge: 'V3',
                        icon: Icons.camera_alt,
                        isSelected: currentMode == MouseMode.optical,
                        isEnabled: false,
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Optical mode is coming in V3'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildModeChip(
                        mode: MouseMode.touchless,
                        label: 'Touchless',
                        badge: 'V4',
                        icon: Icons.back_hand,
                        isSelected: currentMode == MouseMode.touchless,
                        isEnabled: false,
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Touchless mode is coming in V4'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Active Mode View Container
          Expanded(
            child: ListenableBuilder(
              listenable: _modeManager,
              builder: (context, _) {
                final source = _modeManager.activeSource;
                if (source is TouchpadSource) {
                  return TouchpadView(source: source);
                } else if (source is MotionSource) {
                  return MotionView(source: source);
                }
                return const Center(
                  child: Text(
                    'No active mode selected',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip({
    required MouseMode mode,
    required String label,
    required String? badge,
    required IconData icon,
    required bool isSelected,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withAlpha(51)
                : (isEnabled ? const Color(0xFF2A2A36) : const Color(0xFF1E1E24)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Colors.blueAccent
                  : (isEnabled ? Colors.transparent : Colors.white10),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Colors.blueAccent
                    : (isEnabled ? Colors.white70 : Colors.white30),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? Colors.white
                      : (isEnabled ? Colors.white70 : Colors.white38),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A36),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.greenAccent;
      case ConnectionStatus.connecting:
        return Colors.orangeAccent;
      case ConnectionStatus.error:
        return Colors.redAccent;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }
}
