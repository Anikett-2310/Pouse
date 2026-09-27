import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Development / Test helper for Phase 1 Bluetooth Classic RFCOMM Proof of Concept.
class BluetoothRfcommTestService {
  static const MethodChannel _controlChannel = MethodChannel('pouse/rfcomm_control');
  static const EventChannel _statusChannel = EventChannel('pouse/rfcomm_status');

  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('stopped');
  StreamSubscription? _statusSubscription;

  BluetoothRfcommTestService() {
    _listenToStatusEvents();
  }

  void _listenToStatusEvents() {
    _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          statusNotifier.value = event;
        }
      },
      onError: (Object error) {
        statusNotifier.value = 'error: $error';
      },
    );
  }

  Future<bool> startServer() async {
    try {
      final bool? result = await _controlChannel.invokeMethod<bool>('startServer');
      return result ?? false;
    } catch (e) {
      statusNotifier.value = 'error: $e';
      return false;
    }
  }

  Future<bool> stopServer() async {
    try {
      final bool? result = await _controlChannel.invokeMethod<bool>('stopServer');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getStatus() async {
    try {
      final String? result = await _controlChannel.invokeMethod<String>('getStatus');
      return result ?? 'stopped';
    } catch (_) {
      return 'stopped';
    }
  }

  void dispose() {
    _statusSubscription?.cancel();
    statusNotifier.dispose();
  }
}
