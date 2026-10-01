/// Model representing a discovered Pouse PC over BLE advertisement.
class DiscoveredPousePc {
  final String name;
  final String bleAddress;
  final String? classicAddress;
  final int rssi;
  final DateTime lastSeen;
  final bool isMatchedPouseDevice;

  const DiscoveredPousePc({
    required this.name,
    required this.bleAddress,
    this.classicAddress,
    required this.rssi,
    required this.lastSeen,
    required this.isMatchedPouseDevice,
  });

  /// The RFCOMM connection target address (classicAddress if present, else fallback).
  String get targetAddress => classicAddress ?? bleAddress;

  /// Backward-compatible address accessor.
  String get address => targetAddress;

  DiscoveredPousePc copyWith({
    String? name,
    String? bleAddress,
    String? classicAddress,
    int? rssi,
    DateTime? lastSeen,
    bool? isMatchedPouseDevice,
  }) {
    return DiscoveredPousePc(
      name: name ?? this.name,
      bleAddress: bleAddress ?? this.bleAddress,
      classicAddress: classicAddress ?? this.classicAddress,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      isMatchedPouseDevice: isMatchedPouseDevice ?? this.isMatchedPouseDevice,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredPousePc &&
          runtimeType == other.runtimeType &&
          bleAddress == other.bleAddress;

  @override
  int get hashCode => bleAddress.hashCode;

  @override
  String toString() =>
      'DiscoveredPousePc(name: $name, classic: $classicAddress, ble: $bleAddress, rssi: ${rssi}dBm, matched: $isMatchedPouseDevice)';
}

enum BleScanState {
  idle,
  scanning,
  devicesFound,
  noDevicesFound,
  bluetoothDisabled,
  permissionRequired,
  locationRequired,
  scanError,
}
