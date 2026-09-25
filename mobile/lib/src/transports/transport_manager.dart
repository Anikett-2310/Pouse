import 'package:flutter/foundation.dart';
import '../websocket_service.dart';
import 'bluetooth_hid_service.dart';
import 'pouse_transport.dart';

/// Central manager owning the active input transport selection (Wi-Fi or Bluetooth).
///
/// Guarantees that exactly ONE transport is active for input dispatch at any time,
/// and handles transactional transport switching so working connections are not
/// dropped unless the replacement transport is successfully connected and ready.
class TransportManager extends ChangeNotifier {
  final WebSocketService wifiTransport;
  final PouseTransport bluetoothTransport;

  late PouseTransport _activeTransport;
  final ValueNotifier<TransportType> activeTypeNotifier;
  final ValueNotifier<ConnectionStatus> statusNotifier;

  TransportManager({
    required this.wifiTransport,
    required this.bluetoothTransport,
  })  : activeTypeNotifier = ValueNotifier<TransportType>(TransportType.wifi),
        statusNotifier = ValueNotifier<ConnectionStatus>(wifiTransport.status) {
    _activeTransport = wifiTransport;

    // Listen to active transport status updates
    _activeTransport.statusNotifier.addListener(_onActiveStatusChanged);
  }

  PouseTransport get activeTransport => _activeTransport;
  TransportType get activeType => _activeTransport.type;
  ConnectionStatus get status => _activeTransport.status;

  void _onActiveStatusChanged() {
    statusNotifier.value = _activeTransport.status;
    notifyListeners();
  }

  /// Transactionally switches active transport (Wi-Fi <-> Bluetooth).
  ///
  /// Connects to [targetTransport] first. Only when [targetTransport] reaches
  /// [ConnectionStatus.connected] does it release held state on the previous transport,
  /// disconnect it, and swap [activeTransport].
  Future<bool> switchTransport(
    TransportType targetType, {
    String? ipAddress,
    String? wifiIp,
    int wifiPort = 8081,
    String? btAddress,
    String? bluetoothDeviceAddress,
  }) async {
    final hostIp = ipAddress ?? wifiIp;
    final btAddr = btAddress ?? bluetoothDeviceAddress;

    if (targetType == activeType) {
      if (targetType == TransportType.wifi && hostIp != null) {
        await wifiTransport.connect(hostIp, port: wifiPort);
      } else if (targetType == TransportType.bluetooth && btAddr != null && bluetoothTransport is BluetoothHidService) {
        await (bluetoothTransport as BluetoothHidService).connect(btAddr);
      }
      return _activeTransport.status == ConnectionStatus.connected;
    }

    final targetTransport = (targetType == TransportType.wifi)
        ? wifiTransport
        : bluetoothTransport;

    final previousTransport = _activeTransport;

    try {
      if (targetType == TransportType.wifi && hostIp != null) {
        await wifiTransport.connect(hostIp, port: wifiPort);
      } else if (targetType == TransportType.bluetooth && btAddr != null && bluetoothTransport is BluetoothHidService) {
        await (bluetoothTransport as BluetoothHidService).connect(btAddr);
      }

      if (targetTransport.status == ConnectionStatus.connected) {
        // Transactional swap: release held keys/buttons on old transport before disconnecting
        previousTransport.releaseAll();
        if (previousTransport is WebSocketService) {
          await previousTransport.disconnect();
        } else if (previousTransport is BluetoothHidService) {
          await previousTransport.disconnect();
        }

        previousTransport.statusNotifier.removeListener(_onActiveStatusChanged);

        _activeTransport = targetTransport;
        _activeTransport.statusNotifier.addListener(_onActiveStatusChanged);

        activeTypeNotifier.value = targetType;
        statusNotifier.value = targetTransport.status;
        notifyListeners();
        return true;
      } else {
        // Replacement connection failed: keep existing active transport intact
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Forcefully selects active transport (for manual or direct mode selection).
  void setActiveTransport(TransportType targetType) {
    if (targetType == activeType) return;

    final previousTransport = _activeTransport;
    previousTransport.releaseAll();
    previousTransport.statusNotifier.removeListener(_onActiveStatusChanged);

    _activeTransport = (targetType == TransportType.wifi) ? wifiTransport : bluetoothTransport;
    _activeTransport.statusNotifier.addListener(_onActiveStatusChanged);

    activeTypeNotifier.value = targetType;
    statusNotifier.value = _activeTransport.status;
    notifyListeners();
  }

  void releaseAll() {
    _activeTransport.releaseAll();
  }

  @override
  void dispose() {
    _activeTransport.statusNotifier.removeListener(_onActiveStatusChanged);
    activeTypeNotifier.dispose();
    statusNotifier.dispose();
    super.dispose();
  }
}
