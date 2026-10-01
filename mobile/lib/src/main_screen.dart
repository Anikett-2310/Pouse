import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mouse_mode_manager.dart';
import 'pairing_payload.dart';
import 'qr_scanner_screen.dart';
import 'sources/motion_source.dart';
import 'sources/remote_screen_source.dart';
import 'sources/touchpad_source.dart';
import 'sources/touchless_source.dart';
import 'models/discovered_pouse_pc.dart';
import 'models/pouse_trusted_pc.dart';
import 'transports/bluetooth_discovery_service.dart';
import 'transports/bluetooth_hid_service.dart';
import 'transports/bluetooth_rfcomm_service.dart';
import 'transports/pouse_transport.dart';
import 'transports/transport_manager.dart';
import 'utils/constants.dart';
import 'views/motion_view.dart';
import 'views/remote_screen_spike_view.dart';
import 'views/touchpad_view.dart';
import 'views/touchless_view.dart';
import 'websocket_service.dart';
import 'widgets/shared_gesture_guide_dialog.dart';

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
  final BluetoothDiscoveryService _discoveryService = BluetoothDiscoveryService();
  late final TransportManager _transportManager;

  final MouseModeManager _modeManager = MouseModeManager();
  final TextEditingController _ipController = TextEditingController();

  late final TouchpadSource _touchpadSource;
  late final MotionSource _motionSource;
  late final RemoteScreenSource _remoteScreenSource;
  late final TouchlessSource _touchlessSource;

  bool _isBtConnecting = false;
  bool _isRemoteScreenFullscreen = false;

  @override
  void initState() {
    super.initState();
    _transportManager = TransportManager(
      wifiTransport: _wsService,
      bluetoothTransport: _rfcommService,
    );

    _touchpadSource = TouchpadSource(_transportManager.activeTransport);
    _motionSource = MotionSource(_transportManager.activeTransport);
    _remoteScreenSource = RemoteScreenSource(_transportManager.activeTransport);
    _touchlessSource = TouchlessSource(_transportManager.activeTransport);

    _transportManager.addListener(_onActiveTransportChanged);
    _wsService.errorNotifier.addListener(_onWifiErrorChanged);
    _rfcommService.errorNotifier.addListener(_onBtErrorChanged);
    _rfcommService.pendingTrustPcNotifier.addListener(_onPendingTrustChanged);

    _modeManager.registerSource(_touchpadSource);
    _modeManager.registerSource(_motionSource);
    _modeManager.registerSource(_remoteScreenSource);
    _modeManager.registerSource(_touchlessSource);

    _loadSavedIp();
  }

  void _onActiveTransportChanged() {
    setState(() {
      _touchpadSource.setTransport(_transportManager.activeTransport);
      _motionSource.setTransport(_transportManager.activeTransport);
      _remoteScreenSource.setTransport(_transportManager.activeTransport);
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

  Future<void> _savePairToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pouse_pair_token', token);
  }

  Future<String?> _loadSavedPairToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pouse_pair_token');
  }

  Future<void> _openQrScanner() async {
    final payload = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (payload != null && mounted) {
      _ipController.text = payload.host;
      await _saveIp(payload.host);
      if (payload.pairToken != null && payload.pairToken!.isNotEmpty) {
        await _savePairToken(payload.pairToken!);
      }
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
      final pairToken = await _loadSavedPairToken();
      final success = await _transportManager.switchTransport(
        TransportType.wifi,
        ipAddress: ip,
        pairToken: pairToken,
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

  Future<void> _toggleBtConnection({String? targetAddress, String? targetName}) async {
    if (_transportManager.activeType == TransportType.bluetooth &&
        _rfcommService.status == ConnectionStatus.connected) {
      await _rfcommService.disconnect();
    } else {
      final selectedPc = _discoveryService.selectedPcNotifier.value;
      final addr = targetAddress ?? selectedPc?.classicAddress ?? _rfcommService.lastAddress;
      final name = targetName ?? selectedPc?.name ?? _rfcommService.lastName;

      if (addr == null || addr.isEmpty) {
        if (selectedPc != null && (selectedPc.classicAddress == null || selectedPc.classicAddress!.isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pouse PC advertisement missing Classic address'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        _showConnectionMethodSheet();
        return;
      }

      // Clear any stale error from a previous attempt before starting a new one.
      _rfcommService.errorNotifier.value = null;

      setState(() => _isBtConnecting = true);
      final success = await _transportManager.switchTransport(
        TransportType.bluetooth,
        btAddress: addr,
        btName: name,
      );
      if (mounted) {
        setState(() => _isBtConnecting = false);
      }

      // switchTransport returns true when status is connecting OR connected,
      // since the actual RFCOMM connection is completed asynchronously on a
      // worker thread.  Only show the error snackbar on a hard synchronous
      // failure (e.g., Bluetooth adapter disabled, invalid address).
      if (!success && mounted) {
        final btStatus = _rfcommService.status;
        final isAsyncInProgress = btStatus == ConnectionStatus.connecting ||
            btStatus == ConnectionStatus.connected;
        if (!isAsyncInProgress) {
          final err = _rfcommService.errorNotifier.value;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err ?? 'Failed to connect via Bluetooth. Ensure Pouse is running on PC.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  // ── Trust Dialog State ──────────────────────────────────────────────────────

  bool _isTrustDialogVisible = false;

  void _onPendingTrustChanged() {
    final pending = _rfcommService.pendingTrustPcNotifier.value;
    if (pending != null && !_isTrustDialogVisible && mounted) {
      _showTrustDialog(pending);
    } else if (pending == null && _isTrustDialogVisible && mounted) {
      // Auto-dismiss if trust was resolved externally (e.g., disconnect)
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  Future<void> _showTrustDialog(PouseTrustedPc pc) async {
    if (!mounted) return;
    _isTrustDialogVisible = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A24),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Shield icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.cyanAccent,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Text(
                'Trust this PC?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'A PC is requesting Bluetooth control.\n'
                'Only trust devices you own.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Device info card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF252535),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.computer_rounded, color: Colors.cyanAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pc.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pc.classicAddress,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Trust button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await _rfcommService.confirmTrust(pc);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                  label: const Text(
                    'Trust this PC',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent.shade700,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Reject button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    await _rfcommService.rejectTrust();
                  },
                  icon: const Icon(Icons.block_rounded, size: 20),
                  label: const Text(
                    'Reject Connection',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    _isTrustDialogVisible = false;
  }

  @override
  void dispose() {
    _transportManager.removeListener(_onActiveTransportChanged);
    _wsService.errorNotifier.removeListener(_onWifiErrorChanged);
    _rfcommService.errorNotifier.removeListener(_onBtErrorChanged);
    _rfcommService.pendingTrustPcNotifier.removeListener(_onPendingTrustChanged);
    _transportManager.dispose();
    _wsService.dispose();
    _rfcommService.dispose();
    _btHidService.dispose();
    _discoveryService.dispose();
    _ipController.dispose();
    _modeManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: _isRemoteScreenFullscreen
          ? null
          : AppBar(
              title: Row(
                children: [
                  const Icon(Icons.mouse, color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _modeManager,
                      builder: (context, _) {
                        final source = _modeManager.activeSource;
                        final modeName = source?.displayName ?? 'Touchpad';
                        return Text(
                          'Pouse — $modeName',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Guide / Tour Button
                  IconButton(
                    onPressed: () => showPouseGestureGuide(context),
                    icon: const Icon(Icons.help_outline, color: Colors.cyanAccent, size: 20),
                    tooltip: 'Pouse Guide & Tour',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  const SizedBox(width: 4),
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
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: !_isRemoteScreenFullscreen,
        child: Column(
          children: [
            if (!_isRemoteScreenFullscreen) ...[
              // Compact Connection & IP Header Bar [ 📶 192.168.1.12 ] [▣] [ ⏻ ]
              _buildCompactConnectionHeader(),

              // Equal-Width Responsive Mode Selector Row [ 👆 Touchpad ] [ ◉ Motion ] [ ✋ Touchless ]
              _buildModeSelectorBar(),
            ],

            // Active Mode Main Interaction View Container
            Expanded(
              child: ListenableBuilder(
                listenable: _modeManager,
                builder: (context, _) {
                  final source = _modeManager.activeSource;
                  if (source is TouchpadSource) {
                    return TouchpadView(
                      source: source,
                      onRemoteScreenShortcut: () => _modeManager.selectMode(MouseMode.remoteScreen),
                    );
                  } else if (source is MotionSource) {
                    return MotionView(
                      source: source,
                      onRemoteScreenShortcut: () => _modeManager.selectMode(MouseMode.remoteScreen),
                    );
                  } else if (source is RemoteScreenSource) {
                    return RemoteScreenSpikeView(
                      source: source,
                      initialHost: _ipController.text.trim(),
                      onFullscreenChanged: (isFs) {
                        if (_isRemoteScreenFullscreen != isFs && mounted) {
                          setState(() {
                            _isRemoteScreenFullscreen = isFs;
                          });
                        }
                      },
                    );
                  } else if (source is TouchlessSource) {
                    return TouchlessView(
                      source: source,
                      onRemoteScreenShortcut: () => _modeManager.selectMode(MouseMode.remoteScreen),
                    );
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
      final btName = _rfcommService.lastName ?? _discoveryService.selectedPcNotifier.value?.name ?? 'Bluetooth';
      if (btStatus == ConnectionStatus.connected) {
        transportLabel = 'Bluetooth · $btName';
      } else if (btStatus == ConnectionStatus.connecting) {
        transportLabel = 'Bluetooth · Connecting...';
      } else {
        transportLabel = 'Bluetooth · $btName';
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

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: SingleChildScrollView(
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
                  const SizedBox(height: 14),

                  // 💻 Download PC Client Card
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F1F2B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E2E3E)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.laptop_windows, color: Colors.blueAccent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Need the Windows Client?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppConstants.pcClientDownloadUrl,
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: AppConstants.pcClientDownloadUrl),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Download link copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy', style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ),

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

                        // BLE Discovery Section
                        Row(
                          children: [
                            Expanded(
                              child: ValueListenableBuilder<BleScanState>(
                                valueListenable: _discoveryService.scanStateNotifier,
                                builder: (context, scanState, _) {
                                  final isScanning = scanState == BleScanState.scanning;
                                  return ElevatedButton.icon(
                                    onPressed: () {
                                      if (isScanning) {
                                        _discoveryService.stopScan();
                                      } else {
                                        _discoveryService.startScan();
                                      }
                                      setSheetState(() {});
                                    },
                                    icon: isScanning
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.radar, size: 16),
                                    label: Text(
                                      isScanning ? 'Scanning for Pouse PCs...' : 'BLE Scan for Nearby PCs',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isScanning ? Colors.purple.shade800 : const Color(0xFF18181E),
                                      foregroundColor: Colors.purpleAccent,
                                      minimumSize: const Size(0, 38),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: isScanning ? Colors.purpleAccent : Colors.purpleAccent.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // BLE Status Message / Warnings
                        ValueListenableBuilder<String?>(
                          valueListenable: _discoveryService.userMessageNotifier,
                          builder: (context, msg, _) {
                            if (msg == null || msg.isEmpty) return const SizedBox.shrink();
                            final scanState = _discoveryService.scanStateNotifier.value;
                            Color textColor = Colors.white70;
                            if (scanState == BleScanState.locationRequired ||
                                scanState == BleScanState.permissionRequired ||
                                scanState == BleScanState.bluetoothDisabled ||
                                scanState == BleScanState.scanError) {
                              textColor = Colors.orangeAccent;
                            } else if (scanState == BleScanState.scanning) {
                              textColor = Colors.cyanAccent;
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                msg,
                                style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            );
                          },
                        ),

                        // Discovered PCs List
                        ValueListenableBuilder<List<DiscoveredPousePc>>(
                          valueListenable: _discoveryService.discoveredDevicesNotifier,
                          builder: (context, devices, _) {
                            if (devices.isEmpty) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Available Pouse PCs (BLE)',
                                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                if (_rfcommService.lastAddress != null &&
                                    !devices.any((d) => d.classicAddress == _rfcommService.lastAddress))
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.history, color: Colors.white38, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Saved PC: ${_rfcommService.lastName ?? _rfcommService.lastAddress} (Unavailable - out of range)',
                                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ...devices.map((pc) {
                                  final isSelected = _discoveryService.selectedPcNotifier.value?.address == pc.address;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: pc.isMatchedPouseDevice
                                          ? const Color(0xFF281E3D)
                                          : const Color(0xFF1C1C26),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.purpleAccent
                                            : (pc.isMatchedPouseDevice ? Colors.purple.shade400 : Colors.white12),
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          pc.isMatchedPouseDevice ? Icons.laptop_windows : Icons.devices_other,
                                          color: pc.isMatchedPouseDevice ? Colors.purpleAccent : Colors.white54,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      pc.name,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (pc.isMatchedPouseDevice) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.purpleAccent.withValues(alpha: 0.3),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        'Pouse PC',
                                                        style: TextStyle(
                                                          color: Colors.purpleAccent,
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              Text(
                                                pc.classicAddress != null
                                                    ? 'Classic: ${pc.classicAddress!} • BLE: ${pc.bleAddress} • ${pc.rssi} dBm'
                                                    : 'BLE: ${pc.bleAddress} • ${pc.rssi} dBm',
                                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: isBtConnecting
                                              ? null
                                              : () async {
                                                  _discoveryService.selectPc(pc);
                                                  if (isBtConnected && isSelected) {
                                                    await _rfcommService.disconnect();
                                                  } else {
                                                    final targetAddr = pc.classicAddress;
                                                    if (targetAddr == null || targetAddr.isEmpty) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text('Pouse PC advertisement missing Classic address'),
                                                          backgroundColor: Colors.redAccent,
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    await _toggleBtConnection(
                                                      targetAddress: targetAddr,
                                                      targetName: pc.name,
                                                    );
                                                  }
                                                  setSheetState(() {});
                                                  if (mounted) setState(() {});
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: (isBtConnected && isSelected)
                                                ? Colors.redAccent
                                                : (isSelected ? Colors.green.shade700 : Colors.purple.shade700),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: isBtConnecting && isSelected
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : Text(
                                                  (isBtConnected && isSelected) ? 'Disconnect' : 'Connect',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),

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

                        // ── Trusted PC Row ──────────────────────────────────
                        ValueListenableBuilder<List<PouseTrustedPc>>(
                          valueListenable: _rfcommService.trustService.trustedPcsNotifier,
                          builder: (context, trustedList, _) {
                            final savedAddr = _rfcommService.lastAddress;
                            if (savedAddr == null || trustedList.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final addrUpper = savedAddr.toUpperCase();
                            final trusted = trustedList.where(
                              (p) => p.classicAddress.toUpperCase() == addrUpper ||
                                     p.id.toUpperCase() == addrUpper,
                            );
                            if (trusted.isEmpty) return const SizedBox.shrink();
                            final pc = trusted.first;
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_user_rounded,
                                      color: Colors.greenAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Trusted: ${pc.name}',
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            pc.classicAddress,
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        Navigator.pop(modalContext);
                                        await _showForgetPcDialog(pc);
                                        if (mounted) setState(() {});
                                      },
                                      icon: const Icon(
                                        Icons.link_off_rounded,
                                        size: 14,
                                        color: Colors.orangeAccent,
                                      ),
                                      label: const Text(
                                        'Forget',
                                        style: TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Shows a confirmation dialog to forget (revoke trust for) a trusted PC.
  ///
  /// Behavior:
  /// - If the PC is currently connected and active, the active session is preserved
  ///   (not force-disconnected) but trust is revoked immediately. The user will
  ///   be shown a TOFU dialog on the next reconnect.
  /// - If the PC is not currently connected, trust is silently removed.
  Future<void> _showForgetPcDialog(PouseTrustedPc pc) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.link_off_rounded, color: Colors.orangeAccent, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Forget ${pc.name}?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will remove the trust record for this PC. '
              'The next Bluetooth connection will require re-authorization.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.computer_rounded, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pc.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          pc.classicAddress,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note: This does not remove the Android OS Bluetooth bond. '
              'OS pairing and Pouse authorization are separate.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Forget', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _rfcommService.trustService.forgetPc(pc.classicAddress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pc.name} removed from trusted PCs'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildModeSelectorBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              const SizedBox(width: 4),
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
              const SizedBox(width: 4),
              Expanded(
                child: _buildEqualModeButton(
                  mode: MouseMode.remoteScreen,
                  label: 'Remote Screen',
                  icon: Icons.desktop_windows,
                  isSelected: currentMode == MouseMode.remoteScreen,
                  isEnabled: true,
                  onTap: () => _modeManager.selectMode(MouseMode.remoteScreen),
                ),
              ),
              const SizedBox(width: 4),
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
          padding: const EdgeInsets.symmetric(horizontal: 2),
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
                size: 13.5,
                color: isSelected
                    ? Colors.blueAccent
                    : (isEnabled ? Colors.white70 : Colors.white30),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
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
