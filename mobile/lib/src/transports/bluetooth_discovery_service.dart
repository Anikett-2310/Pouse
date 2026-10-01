import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/discovered_pouse_pc.dart';

/// Production BLE Discovery Service for scanning and managing nearby Pouse PCs.
class BluetoothDiscoveryService {
  static const MethodChannel _controlChannel = MethodChannel('pouse/ble_scanner_control');
  static const EventChannel _eventChannel = EventChannel('pouse/ble_scanner_events');

  final ValueNotifier<List<DiscoveredPousePc>> discoveredDevicesNotifier =
      ValueNotifier<List<DiscoveredPousePc>>([]);

  final ValueNotifier<BleScanState> scanStateNotifier =
      ValueNotifier<BleScanState>(BleScanState.idle);

  final ValueNotifier<DiscoveredPousePc?> selectedPcNotifier =
      ValueNotifier<DiscoveredPousePc?>(null);

  final ValueNotifier<String?> userMessageNotifier = ValueNotifier<String?>(null);

  StreamSubscription? _eventSubscription;
  Timer? _stalePruneTimer;

  BluetoothDiscoveryService() {
    _subscribeToEventChannel();
  }

  void _subscribeToEventChannel() {
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic rawEvent) {
          if (rawEvent is Map) {
            _handleNativeEvent(Map<String, dynamic>.from(rawEvent));
          }
        },
        onError: (dynamic error) {
          debugPrint('[BLE] Scanner channel error: $error');
          scanStateNotifier.value = BleScanState.scanError;
          userMessageNotifier.value = 'BLE Scanner error: $error';
        },
      );
    } catch (e) {
      debugPrint('[BLE] Failed to subscribe to BLE scanner event channel: $e');
    }
  }

  void _handleNativeEvent(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    if (event == 'state_changed') {
      final stateStr = data['state'] as String?;
      _parseState(stateStr);
    } else if (event == 'pc_discovered') {
      final name = (data['name'] as String?) ?? 'Pouse PC';
      final bleAddress = (data['bleAddress'] as String?) ?? (data['address'] as String?) ?? '';
      final classicAddress = data['classicAddress'] as String?;
      final rssi = (data['rssi'] as int?) ?? -100;
      final matched = (data['matched'] as bool?) ?? false;

      if (bleAddress.isNotEmpty || (classicAddress != null && classicAddress.isNotEmpty)) {
        _addOrUpdateDevice(
          DiscoveredPousePc(
            name: name,
            bleAddress: bleAddress,
            classicAddress: (classicAddress != null && classicAddress.isNotEmpty) ? classicAddress : null,
            rssi: rssi,
            lastSeen: DateTime.now(),
            isMatchedPouseDevice: matched,
          ),
        );
      }
    } else if (event == 'error') {
      final msg = (data['message'] as String?) ?? 'Scan error';
      userMessageNotifier.value = msg;
    }
  }

  void _parseState(String? stateStr) {
    switch (stateStr) {
      case 'SCANNING':
        scanStateNotifier.value = BleScanState.scanning;
        userMessageNotifier.value = 'Scanning for nearby Pouse PCs...';
        _startStalePruneTimer();
        break;
      case 'DEVICES_FOUND':
        scanStateNotifier.value = BleScanState.devicesFound;
        userMessageNotifier.value = 'Discovered ${discoveredDevicesNotifier.value.length} PC(s)';
        _stopStalePruneTimer();
        break;
      case 'NO_DEVICES_FOUND':
        scanStateNotifier.value = BleScanState.noDevicesFound;
        userMessageNotifier.value = 'No Pouse PCs found nearby';
        _stopStalePruneTimer();
        break;
      case 'BLUETOOTH_DISABLED':
        scanStateNotifier.value = BleScanState.bluetoothDisabled;
        userMessageNotifier.value = 'Bluetooth is turned off';
        break;
      case 'PERMISSION_REQUIRED':
        scanStateNotifier.value = BleScanState.permissionRequired;
        userMessageNotifier.value = 'Bluetooth scan permission required';
        break;
      case 'LOCATION_REQUIRED':
        scanStateNotifier.value = BleScanState.locationRequired;
        userMessageNotifier.value = 'Location Services must be enabled on Android 10';
        break;
      case 'SCAN_ERROR':
        scanStateNotifier.value = BleScanState.scanError;
        break;
      default:
        scanStateNotifier.value = BleScanState.idle;
    }
  }

  void _addOrUpdateDevice(DiscoveredPousePc device) {
    final currentList = List<DiscoveredPousePc>.from(discoveredDevicesNotifier.value);
    final index = currentList.indexWhere((d) {
      if (device.classicAddress != null && d.classicAddress != null) {
        return d.classicAddress == device.classicAddress;
      }
      return d.address == device.address || d.bleAddress == device.bleAddress;
    });

    if (index >= 0) {
      currentList[index] = device;
    } else {
      currentList.add(device);
    }

    // Sort list: matched Pouse PCs at top, then higher RSSI
    currentList.sort((a, b) {
      if (a.isMatchedPouseDevice != b.isMatchedPouseDevice) {
        return a.isMatchedPouseDevice ? -1 : 1;
      }
      return b.rssi.compareTo(a.rssi);
    });

    discoveredDevicesNotifier.value = currentList;
    if (scanStateNotifier.value == BleScanState.scanning) {
      userMessageNotifier.value = 'Discovered ${currentList.length} device(s)...';
    }
  }

  Future<bool> startScan() async {
    try {
      discoveredDevicesNotifier.value = [];
      selectedPcNotifier.value = null;
      userMessageNotifier.value = 'Initiating BLE scan...';
      final bool? result = await _controlChannel.invokeMethod<bool>('startScan');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('[BLE] startScan PlatformException: ${e.message}');
      userMessageNotifier.value = 'BLE Scan error: ${e.message}';
      scanStateNotifier.value = BleScanState.scanError;
      return false;
    } catch (e) {
      debugPrint('[BLE] startScan error: $e');
      return false;
    }
  }

  Future<void> stopScan() async {
    try {
      await _controlChannel.invokeMethod<bool>('stopScan');
    } catch (e) {
      debugPrint('[BLE] stopScan error: $e');
    }
    _stopStalePruneTimer();
  }

  void selectPc(DiscoveredPousePc pc) {
    selectedPcNotifier.value = pc;
    userMessageNotifier.value = 'Selected ${pc.name} (${pc.address})';
  }

  void _startStalePruneTimer() {
    _stalePruneTimer?.cancel();
    _stalePruneTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      final now = DateTime.now();
      final filtered = discoveredDevicesNotifier.value
          .where((d) => now.difference(d.lastSeen).inSeconds < 15)
          .toList();
      if (filtered.length != discoveredDevicesNotifier.value.length) {
        discoveredDevicesNotifier.value = filtered;
      }
    });
  }

  void _stopStalePruneTimer() {
    _stalePruneTimer?.cancel();
    _stalePruneTimer = null;
  }

  void dispose() {
    _eventSubscription?.cancel();
    _stalePruneTimer?.cancel();
    discoveredDevicesNotifier.dispose();
    scanStateNotifier.dispose();
    selectedPcNotifier.dispose();
    userMessageNotifier.dispose();
  }
}
