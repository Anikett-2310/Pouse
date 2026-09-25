import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mouse_mode_manager.dart';
import 'pairing_payload.dart';
import 'qr_scanner_screen.dart';
import 'sources/motion_source.dart';
import 'sources/touchpad_source.dart';
import 'sources/touchless_source.dart';
import 'transports/bluetooth_hid_service.dart';
import 'transports/pouse_transport.dart';
import 'transports/transport_manager.dart';
import 'views/motion_view.dart';
import 'views/touchpad_view.dart';
import 'views/touchless_view.dart';
import 'websocket_service.dart';

/// The Unified App Shell for Pouse.
///
/// Houses dual transport mode selection (Wi-Fi WebSocket / Bluetooth HID),
/// QR scanner, manual IP input, Bluetooth paired device selection, connection status,
/// and renders active mode views (Touchpad / Motion / Touchless) driven by [MouseModeManager].
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final WebSocketService _wsService = WebSocketService();
  final BluetoothHidService _btService = BluetoothHidService();
  late final TransportManager _transportManager;

  final MouseModeManager _modeManager = MouseModeManager();
  final TextEditingController _ipController = TextEditingController();

  late final TouchpadSource _touchpadSource;
  late final MotionSource _motionSource;
  late final TouchlessSource _touchlessSource;

  // Bluetooth State
  bool _isBtSupported = false;
  bool _isBtChecking = true;
  List<Map<String, String>> _pairedDevices = [];
  String? _selectedBtAddress;
  bool _isBtConnecting = false;

  @override
  void initState() {
    super.initState();
    _transportManager = TransportManager(
      wifiTransport: _wsService,
      bluetoothTransport: _btService,
    );

    _touchpadSource = TouchpadSource(_transportManager.activeTransport);
    _motionSource = MotionSource(_transportManager.activeTransport);
    _touchlessSource = TouchlessSource(_transportManager.activeTransport);

    _transportManager.addListener(_onActiveTransportChanged);
    _wsService.errorNotifier.addListener(_onWifiErrorChanged);
    _btService.errorNotifier.addListener(_onBtErrorChanged);

    _modeManager.registerSource(_touchpadSource);
    _modeManager.registerSource(_motionSource);
    _modeManager.registerSource(_touchlessSource);

    _loadSavedIp();
    _checkBtSupport();
  }

  void _onActiveTransportChanged() {
    setState(() {
      _touchpadSource.setTransport(_transportManager.activeTransport);
      _motionSource.setTransport(_transportManager.activeTransport);
      _touchlessSource.setTransport(_transportManager.activeTransport);
    });
  }

  void _onWifiErrorChanged() {
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

  void _onBtErrorChanged() {
    final error = _btService.errorNotifier.value;
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

  Future<void> _checkBtSupport() async {
    setState(() => _isBtChecking = true);
    try {
      final supported = await _btService.isSupported();
      setState(() {
        _isBtSupported = supported;
        _isBtChecking = false;
      });
      if (supported) {
        await _refreshPairedDevices();
      }
    } catch (_) {
      setState(() {
        _isBtSupported = false;
        _isBtChecking = false;
      });
    }
  }

  Future<void> _refreshPairedDevices() async {
    try {
      final hasPerm = await _btService.requestPermissions();
      if (hasPerm) {
        final devices = await _btService.getPairedDevices();
        setState(() {
          _pairedDevices = devices;
          if (_selectedBtAddress == null && devices.isNotEmpty) {
            _selectedBtAddress = devices.first['address'];
          }
        });
      }
    } catch (_) {}
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

      _toggleWifiConnection();
    }
  }

  Future<void> _toggleWifiConnection() async {
    if (_transportManager.activeType == TransportType.wifi &&
        _wsService.status == ConnectionStatus.connected) {
      await _wsService.disconnect();
    } else {
      final ip = _ipController.text.trim();
      if (ip.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your PC IP address')),
        );
        return;
      }
      _saveIp(ip);
      final success = await _transportManager.switchTransport(
        TransportType.wifi,
        ipAddress: ip,
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect via Wi-Fi. Check PC client status.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _toggleBtConnection() async {
    if (_transportManager.activeType == TransportType.bluetooth &&
        _btService.status == ConnectionStatus.connected) {
      await _btService.disconnect();
    } else {
      if (_selectedBtAddress == null || _selectedBtAddress!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a paired Bluetooth device')),
        );
        return;
      }
      setState(() => _isBtConnecting = true);
      final success = await _transportManager.switchTransport(
        TransportType.bluetooth,
        btAddress: _selectedBtAddress,
      );
      setState(() => _isBtConnecting = false);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect via Bluetooth HID. Ensure device is paired and Windows Bluetooth is active.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _transportManager.removeListener(_onActiveTransportChanged);
    _wsService.errorNotifier.removeListener(_onWifiErrorChanged);
    _btService.errorNotifier.removeListener(_onBtErrorChanged);
    _transportManager.dispose();
    _wsService.dispose();
    _btService.dispose();
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
            const Icon(Icons.mouse, color: Colors.blueAccent, size: 20),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _modeManager,
              builder: (context, _) {
                final source = _modeManager.activeSource;
                final modeName = source?.displayName ?? 'Touchpad';
                return Text(
                  'Pouse — $modeName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                );
              },
            ),
            const Spacer(),
            // Compact Connection Status Dot (●)
            ValueListenableBuilder<TransportType>(
              valueListenable: ValueNotifier(_transportManager.activeType),
              builder: (context, transportType, child) {
                final isWifi = _transportManager.activeType == TransportType.wifi;
                final statusNotifier = isWifi ? _wsService.statusNotifier : _btService.statusNotifier;

                return ValueListenableBuilder<ConnectionStatus>(
                  valueListenable: statusNotifier,
                  builder: (context, status, child) {
                    return Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getStatusColor(status).withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E24),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Compact Connection & IP Header Bar [ 📶 192.168.1.12 ] [▣] [ ⏻ ]
          _buildCompactConnectionHeader(),

          // Equal-Width Responsive Mode Selector Row [ 👆 Touchpad ] [ ◉ Motion ] [ ✋ Touchless ]
          _buildModeSelectorBar(),

          // Active Mode Main Interaction View Container
          Expanded(
            child: ListenableBuilder(
              listenable: _modeManager,
              builder: (context, _) {
                final source = _modeManager.activeSource;
                if (source is TouchpadSource) {
                  return TouchpadView(source: source);
                } else if (source is MotionSource) {
                  return MotionView(source: source);
                } else if (source is TouchlessSource) {
                  return TouchlessView(source: source);
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

  Widget _buildCompactConnectionHeader() {
    final isWifi = _transportManager.activeType == TransportType.wifi;
    final statusNotifier = isWifi ? _wsService.statusNotifier : _btService.statusNotifier;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF18181E),
      child: Row(
        children: [
          // Compact IP Input / Bluetooth Device Pill [ 📶 192.168.1.12 ]
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A36),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () async {
                      final nextType = isWifi ? TransportType.bluetooth : TransportType.wifi;
                      if (nextType == TransportType.wifi) {
                        await _toggleWifiConnection();
                      } else {
                        await _toggleBtConnection();
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
                      child: Icon(
                        isWifi ? Icons.wifi : Icons.bluetooth,
                        color: isWifi ? Colors.blueAccent : Colors.cyanAccent,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: isWifi
                        ? TextField(
                            controller: _ipController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              hintText: '192.168.1.x',
                              hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        : _isBtChecking
                            ? const Text(
                                'Checking BT...',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              )
                            : !_isBtSupported
                                ? const Text(
                                    'BT Profile Unavailable',
                                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                                  )
                                : DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedBtAddress,
                                      hint: const Text('Select Paired PC', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                      dropdownColor: const Color(0xFF2A2A36),
                                      isExpanded: true,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      items: _pairedDevices.map((device) {
                                        final name = device['name'] ?? 'Unknown PC';
                                        final address = device['address'] ?? '';
                                        return DropdownMenuItem<String>(
                                          value: address,
                                          child: Text(
                                            '$name ($address)',
                                            style: const TextStyle(color: Colors.white, fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setState(() => _selectedBtAddress = val),
                                    ),
                                  ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // QR Scanner Button [ ▣ ]
          IconButton.filled(
            onPressed: isWifi ? _openQrScanner : _refreshPairedDevices,
            icon: Icon(isWifi ? Icons.qr_code_scanner : Icons.refresh, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A36),
              foregroundColor: isWifi ? Colors.blueAccent : Colors.cyanAccent,
              minimumSize: const Size(38, 38),
              maximumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            tooltip: isWifi ? 'Scan PC QR Code' : 'Refresh Bluetooth Devices',
          ),
          const SizedBox(width: 8),

          // Connect / Disconnect Power Button [ ⏻ ]
          ValueListenableBuilder<ConnectionStatus>(
            valueListenable: statusNotifier,
            builder: (context, status, child) {
              final isConnected = status == ConnectionStatus.connected;
              final isConnecting = status == ConnectionStatus.connecting || _isBtConnecting;

              return IconButton.filled(
                onPressed: isConnecting ? null : () => isWifi ? _toggleWifiConnection() : _toggleBtConnection(),
                icon: isConnecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        isConnected ? Icons.power_settings_new : Icons.link,
                        size: 18,
                      ),
                style: IconButton.styleFrom(
                  backgroundColor: isConnected ? Colors.redAccent : (isWifi ? Colors.blueAccent : Colors.cyanAccent.shade700),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(38, 38),
                  maximumSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                tooltip: isConnected ? 'Disconnect' : 'Connect',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelectorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF16161B),
      child: ListenableBuilder(
        listenable: _modeManager,
        builder: (context, _) {
          final currentMode = _modeManager.currentMode;
          return Row(
            children: [
              Expanded(
                child: _buildEqualModeButton(
                  mode: MouseMode.touchpad,
                  label: 'Touchpad',
                  icon: Icons.touch_app,
                  isSelected: currentMode == MouseMode.touchpad,
                  isEnabled: true,
                  onTap: () => _modeManager.selectMode(MouseMode.touchpad),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildEqualModeButton(
                  mode: MouseMode.motion,
                  label: 'Motion',
                  icon: Icons.screen_rotation,
                  isSelected: currentMode == MouseMode.motion,
                  isEnabled: true,
                  onTap: () => _modeManager.selectMode(MouseMode.motion),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildEqualModeButton(
                  mode: MouseMode.touchless,
                  label: 'Touchless',
                  icon: Icons.back_hand,
                  isSelected: currentMode == MouseMode.touchless,
                  isEnabled: true,
                  onTap: () => _modeManager.selectMode(MouseMode.touchless),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEqualModeButton({
    required MouseMode mode,
    required String label,
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
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blueAccent.withValues(alpha: 0.25)
                : (isEnabled ? const Color(0xFF2A2A36) : const Color(0xFF1E1E24)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Colors.blueAccent
                  : Colors.white.withValues(alpha: 0.06),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? Colors.blueAccent
                    : (isEnabled ? Colors.white70 : Colors.white30),
              ),
              const SizedBox(width: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isEnabled ? Colors.white70 : Colors.white38),
                  ),
                ),
              ),
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
