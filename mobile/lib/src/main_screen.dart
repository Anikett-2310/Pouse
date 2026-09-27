import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mouse_mode_manager.dart';
import 'pairing_payload.dart';
import 'qr_scanner_screen.dart';
import 'sources/motion_source.dart';
import 'sources/touchpad_source.dart';
import 'sources/touchless_source.dart';
import 'transports/bluetooth_hid_service.dart';
import 'transports/bluetooth_rfcomm_service.dart';
import 'transports/pouse_transport.dart';
import 'transports/transport_manager.dart';
import 'views/motion_view.dart';
import 'views/touchpad_view.dart';
import 'views/touchless_view.dart';
import 'websocket_service.dart';

/// The Unified App Shell for Pouse.
///
/// Houses dual transport mode selection (Wi-Fi WebSocket / Bluetooth RFCOMM),
/// QR scanner, manual IP input, connection status,
/// and renders active mode views (Touchpad / Motion / Touchless) driven by [MouseModeManager].
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final WebSocketService _wsService = WebSocketService();
  final BluetoothRfcommService _rfcommService = BluetoothRfcommService();
  final BluetoothHidService _btHidService = BluetoothHidService();
  late final TransportManager _transportManager;

  final MouseModeManager _modeManager = MouseModeManager();
  final TextEditingController _ipController = TextEditingController();

  late final TouchpadSource _touchpadSource;
  late final MotionSource _motionSource;
  late final TouchlessSource _touchlessSource;

  bool _isBtConnecting = false;

  @override
  void initState() {
    super.initState();
    _transportManager = TransportManager(
      wifiTransport: _wsService,
      bluetoothTransport: _rfcommService,
    );

    _touchpadSource = TouchpadSource(_transportManager.activeTransport);
    _motionSource = MotionSource(_transportManager.activeTransport);
    _touchlessSource = TouchlessSource(_transportManager.activeTransport);

    _transportManager.addListener(_onActiveTransportChanged);
    _wsService.errorNotifier.addListener(_onWifiErrorChanged);
    _rfcommService.errorNotifier.addListener(_onBtErrorChanged);

    _modeManager.registerSource(_touchpadSource);
    _modeManager.registerSource(_motionSource);
    _modeManager.registerSource(_touchlessSource);

    _loadSavedIp();
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
    final error = _rfcommService.errorNotifier.value;
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
        _rfcommService.status == ConnectionStatus.connected) {
      await _rfcommService.disconnect();
    } else {
      setState(() => _isBtConnecting = true);
      final success = await _transportManager.switchTransport(
        TransportType.bluetooth,
      );
      setState(() => _isBtConnecting = false);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start Bluetooth RFCOMM server. Ensure Bluetooth is active.'),
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
    _rfcommService.errorNotifier.removeListener(_onBtErrorChanged);
    _transportManager.dispose();
    _wsService.dispose();
    _rfcommService.dispose();
    _btHidService.dispose();
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
                final statusNotifier = isWifi ? _wsService.statusNotifier : _rfcommService.statusNotifier;

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
    final statusNotifier = isWifi ? _wsService.statusNotifier : _rfcommService.statusNotifier;

    // Compute display label for transport pill
    String transportLabel;
    if (isWifi) {
      final ip = _ipController.text.trim();
      transportLabel = ip.isNotEmpty ? 'Wi-Fi · $ip' : 'Wi-Fi · Tap to set IP';
    } else {
      final btStatus = _rfcommService.status;
      if (btStatus == ConnectionStatus.connected) {
        transportLabel = 'Bluetooth · Connected';
      } else if (btStatus == ConnectionStatus.connecting) {
        transportLabel = 'Bluetooth · Searching...';
      } else {
        transportLabel = 'Bluetooth · Direct RFCOMM';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF18181E),
      child: Row(
        children: [
          // Compact Transport Pill Button [ 📶 Wi-Fi · 192.168.1.125 ▼ ]
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showConnectionMethodSheet(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A36),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isWifi ? Icons.wifi : Icons.bluetooth,
                        color: isWifi ? Colors.blueAccent : Colors.cyanAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          transportLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.unfold_more,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Action Button (QR Scanner for Wi-Fi / Connect for BT) [ ▣ ]
          IconButton.filled(
            onPressed: isWifi ? _openQrScanner : _toggleBtConnection,
            icon: Icon(isWifi ? Icons.qr_code_scanner : Icons.bluetooth_searching, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A36),
              foregroundColor: isWifi ? Colors.blueAccent : Colors.cyanAccent,
              minimumSize: const Size(38, 38),
              maximumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            tooltip: isWifi ? 'Scan PC QR Code' : 'Bluetooth Connection',
          ),
          const SizedBox(width: 8),

          // Connect / Disconnect Power Button [ ⏻ ]
          ValueListenableBuilder<ConnectionStatus>(
            valueListenable: statusNotifier,
            builder: (context, status, child) {
              final isConnected = status == ConnectionStatus.connected;
              final isConnecting = status == ConnectionStatus.connecting || (!isWifi && _isBtConnecting);

              return IconButton.filled(
                onPressed: isConnecting
                    ? null
                    : () {
                        if (isConnected) {
                          if (isWifi) {
                            _wsService.disconnect();
                          } else {
                            _rfcommService.disconnect();
                          }
                        } else {
                          if (isWifi) {
                            if (_ipController.text.trim().isEmpty) {
                              _showConnectionMethodSheet();
                            } else {
                              _toggleWifiConnection();
                            }
                          } else {
                            _toggleBtConnection();
                          }
                        }
                      },
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
                  backgroundColor: isConnected
                      ? Colors.redAccent
                      : (isWifi ? Colors.blueAccent : Colors.cyanAccent.shade700),
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

  void _showConnectionMethodSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isWifiActive = _transportManager.activeType == TransportType.wifi;
            final isBtActive = _transportManager.activeType == TransportType.bluetooth;

            final wifiStatus = _wsService.status;
            final btStatus = _rfcommService.status;

            final isWifiConnected = isWifiActive && wifiStatus == ConnectionStatus.connected;
            final isWifiConnecting = isWifiActive && wifiStatus == ConnectionStatus.connecting;

            final isBtConnected = isBtActive && btStatus == ConnectionStatus.connected;
            final isBtConnecting = isBtActive && (btStatus == ConnectionStatus.connecting || _isBtConnecting);

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Connection Method',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(modalContext),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 📶 Wi-Fi Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isWifiActive
                          ? Colors.blueAccent.withValues(alpha: 0.12)
                          : const Color(0xFF22222B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isWifiActive
                            ? Colors.blueAccent.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.06),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Wi-Fi',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Local network WebSocket server',
                                    style: TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (isWifiActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blueAccent, width: 1),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // IP Input & Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF18181E),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: TextField(
                                  controller: _ipController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'PC IP (e.g. 192.168.1.125)',
                                    hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  onChanged: (_) => setSheetState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // QR Scan Button
                            IconButton(
                              onPressed: () async {
                                Navigator.pop(modalContext);
                                await _openQrScanner();
                              },
                              icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent, size: 18),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF18181E),
                                minimumSize: const Size(38, 38),
                                maximumSize: const Size(38, 38),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: Colors.white12),
                                ),
                              ),
                              tooltip: 'Scan QR Code',
                            ),
                            const SizedBox(width: 8),

                            // Connect / Disconnect Button
                            ElevatedButton(
                              onPressed: isWifiConnecting
                                  ? null
                                  : () async {
                                      if (isWifiConnected) {
                                        await _wsService.disconnect();
                                      } else {
                                        await _toggleWifiConnection();
                                      }
                                      setSheetState(() {});
                                      if (mounted) setState(() {});
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isWifiConnected ? Colors.redAccent : Colors.blueAccent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: isWifiConnecting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      isWifiConnected
                                          ? 'Disconnect'
                                          : (isWifiActive ? 'Connect' : 'Select / Connect'),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 🔵 Bluetooth Card (RFCOMM)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isBtActive
                          ? Colors.cyanAccent.withValues(alpha: 0.08)
                          : const Color(0xFF22222B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isBtActive
                            ? Colors.cyanAccent.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.06),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bluetooth, color: Colors.cyanAccent, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Bluetooth',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Wireless • Direct RFCOMM (No Wi-Fi)',
                                    style: TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (isBtActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.cyanAccent, width: 1),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Guidance note
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18181E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.info_outline, color: Colors.cyanAccent, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pair phone once in Windows Bluetooth Settings. Pouse connects automatically.',
                                  style: TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Action Button Row
                        Row(
                          children: [
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: _rfcommService.userMessageNotifier,
                                builder: (context, msg, _) {
                                  return Text(
                                    msg,
                                    style: TextStyle(
                                      color: isBtConnected ? Colors.greenAccent : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                            ElevatedButton(
                              onPressed: isBtConnecting
                                  ? null
                                  : () async {
                                      if (isBtConnected) {
                                        await _rfcommService.disconnect();
                                      } else {
                                        await _toggleBtConnection();
                                      }
                                      setSheetState(() {});
                                      if (mounted) setState(() {});
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isBtConnected ? Colors.redAccent : Colors.cyanAccent.shade700,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: isBtConnecting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(
                                      isBtConnected
                                          ? 'Disconnect'
                                          : (isBtActive ? 'Connect' : 'Select & Connect'),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
