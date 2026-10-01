import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pouse_trusted_pc.dart';
import '../services/pouse_trust_service.dart';
import '../websocket_service.dart';
import 'pouse_transport.dart';

/// Production Bluetooth Classic RFCOMM Client Transport implementation.
///
/// Implements [PouseTransport] over an isolated RFCOMM client socket on Android,
/// connecting securely to the Windows Pouse RFCOMM server without Wi-Fi.
class BluetoothRfcommService implements PouseTransport {
  static const MethodChannel _controlChannel = MethodChannel('pouse/rfcomm_control');
  static const EventChannel _statusChannel = EventChannel('pouse/rfcomm_status');

  static const String _prefKeyAddress = 'pouse_bt_last_address';
  static const String _prefKeyName = 'pouse_bt_last_name';

  final PouseTrustService trustService;
  final ValueNotifier<PouseTrustedPc?> pendingTrustPcNotifier =
      ValueNotifier<PouseTrustedPc?>(null);

  @override
  TransportType get type => TransportType.bluetooth;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamSubscription? _statusSubscription;

  String? _lastAddress;
  String? _lastName;

  // Bounded reconnect tracking
  bool _isAutoReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 2;

  // Set to true before an intentional user-driven disconnect so that any
  // racing 'error:' status from the Kotlin read loop is silently ignored.
  bool _intentionalDisconnect = false;

  // Button & Key tracking for safety release
  bool _isLeftButtonDown = false;
  bool _isRightButtonDown = false;
  final Set<String> _heldKeys = {};

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.disconnected);

  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String> userMessageNotifier =
      ValueNotifier<String>('Select a Pouse PC to connect via Bluetooth');

  final ValueNotifier<String?> targetDeviceNotifier = ValueNotifier<String?>(null);

  String? get lastAddress => _lastAddress;
  String? get lastName => _lastName;

  BluetoothRfcommService({PouseTrustService? trustService})
      : trustService = trustService ?? PouseTrustService() {
    _subscribeToStatusStream();
    _loadSavedTarget();
  }

  Future<void> _loadSavedTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastAddress = prefs.getString(_prefKeyAddress);
      _lastName = prefs.getString(_prefKeyName);
      if (_lastAddress != null && _lastAddress!.isNotEmpty) {
        targetDeviceNotifier.value = _lastName ?? _lastAddress;
        userMessageNotifier.value = 'Ready to connect to ${_lastName ?? _lastAddress}';
      }
    } catch (e) {
      debugPrint('[RFCOMM] Error loading saved target: $e');
    }
  }

  Future<void> _saveTarget(String address, String? name) async {
    _lastAddress = address;
    _lastName = name;
    targetDeviceNotifier.value = name ?? address;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyAddress, address);
      if (name != null) {
        await prefs.setString(_prefKeyName, name);
      } else {
        await prefs.remove(_prefKeyName);
      }
    } catch (e) {
      debugPrint('[RFCOMM] Error saving target: $e');
    }
  }

  void _subscribeToStatusStream() {
    try {
      _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
        (dynamic rawStatus) {
          final statusStr = rawStatus.toString();
          _handleNativeStatus(statusStr);
        },
        onError: (dynamic error) {
          debugPrint('[RFCOMM] Status channel error: $error');
          _setStatus(ConnectionStatus.error);
          userMessageNotifier.value = 'Bluetooth error: $error';
        },
      );
    } catch (e) {
      debugPrint('[RFCOMM] Failed to subscribe to status stream: $e');
    }
  }

  void _handleNativeStatus(String statusStr) {
    if (statusStr == 'connected') {
      _intentionalDisconnect = false;
      _reconnectAttempts = 0;
      _isAutoReconnecting = false;
      final devName = _lastName ?? _lastAddress ?? 'Pouse PC';
      final targetAddr = _lastAddress ?? '';

      if (targetAddr.isNotEmpty && !trustService.isTrustedSync(targetAddr)) {
        // First connection: Trust confirmation required
        _setStatus(ConnectionStatus.connecting);
        final pending = PouseTrustedPc(
          id: targetAddr,
          name: devName,
          classicAddress: targetAddr,
          firstTrustedAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
        );
        pendingTrustPcNotifier.value = pending;
        userMessageNotifier.value = 'Trust confirmation required for $devName';
        errorNotifier.value = null;
        debugPrint('[RFCOMM] Session pending user trust confirmation for: $devName ($targetAddr)');
      } else {
        // Already trusted: Automatically authorize
        pendingTrustPcNotifier.value = null;
        _setStatus(ConnectionStatus.connected);
        userMessageNotifier.value = 'Connected to $devName (Trusted)';
        errorNotifier.value = null;
        if (targetAddr.isNotEmpty) {
          trustService.updateLastSeen(targetAddr);
        }
      }
    } else if (statusStr == 'connecting') {
      _setStatus(ConnectionStatus.connecting);
      final devName = _lastName ?? _lastAddress ?? 'Pouse PC';
      userMessageNotifier.value = 'Connecting to $devName...';
    } else if (statusStr == 'pairing') {
      _setStatus(ConnectionStatus.connecting);
      userMessageNotifier.value = 'Pairing with PC... Accept prompt on phone';
    } else if (statusStr == 'pairing_cancelled') {
      _setStatus(ConnectionStatus.error);
      userMessageNotifier.value = 'Pairing cancelled';
      errorNotifier.value = 'Pairing cancelled by user or PC';
      pendingTrustPcNotifier.value = null;
    } else if (statusStr == 'disconnecting') {
      _setStatus(ConnectionStatus.disconnected);
      userMessageNotifier.value = 'Disconnecting...';
      pendingTrustPcNotifier.value = null;
    } else if (statusStr == 'disconnected') {
      final previousStatus = _status;
      _setStatus(ConnectionStatus.disconnected);
      userMessageNotifier.value = 'Disconnected';
      pendingTrustPcNotifier.value = null;

      // Safe bounded reconnect ONLY for unexpected disconnects
      if (previousStatus == ConnectionStatus.connected &&
          !_isAutoReconnecting &&
          !_intentionalDisconnect &&
          _lastAddress != null &&
          _reconnectAttempts < _maxReconnectAttempts) {
        _triggerBoundedReconnect();
      }
    } else if (statusStr.startsWith('error:')) {
      // Ignore racing error: events that arrive after an intentional disconnect.
      // These are stale read-loop exceptions caused by the socket being closed on purpose.
      if (_intentionalDisconnect) {
        debugPrint('[RFCOMM] Ignoring stale error after intentional disconnect: $statusStr');
        return;
      }
      _setStatus(ConnectionStatus.error);
      final msg = statusStr.replaceFirst('error:', '').trim();
      errorNotifier.value = msg;
      userMessageNotifier.value = 'Bluetooth error: $msg';
      pendingTrustPcNotifier.value = null;
    }
  }

  /// Confirms application-level trust for the connected PC (Trust On First Use).
  Future<void> confirmTrust(PouseTrustedPc pc) async {
    await trustService.trustPc(
      id: pc.id,
      name: pc.name,
      classicAddress: pc.classicAddress,
    );
    pendingTrustPcNotifier.value = null;
    _setStatus(ConnectionStatus.connected);
    userMessageNotifier.value = 'Connected to ${pc.name} (Trusted)';
    debugPrint('[RFCOMM] User confirmed trust for: ${pc.name} (${pc.classicAddress})');
  }

  /// Rejects application-level trust for the connected PC. Closes connection immediately.
  Future<void> rejectTrust() async {
    pendingTrustPcNotifier.value = null;
    await disconnect();
    userMessageNotifier.value = 'Trust rejected. Connection closed.';
    errorNotifier.value = 'Trust rejected by user';
    debugPrint('[RFCOMM] User rejected trust. Disconnecting.');
  }

  void _triggerBoundedReconnect() {
    _isAutoReconnecting = true;
    _reconnectAttempts++;
    final retryDelaySec = _reconnectAttempts * 2;
    debugPrint('[RFCOMM] Auto-reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${retryDelaySec}s...');
    userMessageNotifier.value = 'Reconnecting in ${retryDelaySec}s (attempt $_reconnectAttempts)...';

    Timer(Duration(seconds: retryDelaySec), () async {
      if (_status != ConnectionStatus.connected && _lastAddress != null) {
        await connect(_lastAddress!, name: _lastName);
      }
      _isAutoReconnecting = false;
    });
  }

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected && pendingTrustPcNotifier.value == null;

  /// Connects to a specific discovered Bluetooth PC address using secure RFCOMM.
  Future<bool> connect(String address, {String? name}) async {
    try {
      _setStatus(ConnectionStatus.connecting);
      final displayName = name ?? address;
      userMessageNotifier.value = 'Connecting to $displayName...';
      errorNotifier.value = null;

      await _saveTarget(address, name);

      final bool? result = await _controlChannel.invokeMethod<bool>('connect', {
        'address': address,
        'name': name,
      });

      if (result == true) {
        return true;
      } else {
        _setStatus(ConnectionStatus.error);
        userMessageNotifier.value = 'Failed to connect to $displayName';
        return false;
      }
    } on PlatformException catch (e) {
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = e.message;
      userMessageNotifier.value = 'Bluetooth error: ${e.message}';
      return false;
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = e.toString();
      userMessageNotifier.value = 'Bluetooth error: $e';
      return false;
    }
  }

  /// Connects to the last saved target address if available.
  Future<bool> connectLastOrSaved() async {
    if (_lastAddress == null) {
      await _loadSavedTarget();
    }
    if (_lastAddress != null && _lastAddress!.isNotEmpty) {
      return connect(_lastAddress!, name: _lastName);
    } else {
      _setStatus(ConnectionStatus.error);
      userMessageNotifier.value = 'No Pouse PC selected. Please scan first.';
      return false;
    }
  }

  /// Legacy startServer compatibility shim.
  Future<bool> startServer() async {
    return connectLastOrSaved();
  }

  Future<void> disconnect() async {
    _isAutoReconnecting = false;
    _reconnectAttempts = 0;
    _intentionalDisconnect = true;  // Must be set before invoking native disconnect
    pendingTrustPcNotifier.value = null;
    releaseAll();
    try {
      await _controlChannel.invokeMethod<bool>('disconnect');
    } catch (e) {
      debugPrint('[RFCOMM] Error disconnecting: $e');
    }
    _setStatus(ConnectionStatus.disconnected);
    userMessageNotifier.value = 'Disconnected';
  }

  void sendEvent(Map<String, dynamic> event) {
    if (_status == ConnectionStatus.connected && pendingTrustPcNotifier.value == null) {
      if (event['event'] != 'MOVE' && (_pendingMoveDx != 0 || _pendingMoveDy != 0)) {
        _flushMove();
      }
      try {
        final jsonString = jsonEncode(event);
        _controlChannel.invokeMethod<bool>('sendEvent', {'message': jsonString});
      } catch (e) {
        debugPrint('[RFCOMM] Failed to send event: $e');
      }
    }
  }

  // Microtask Coalescing for MOVE events
  double _pendingMoveDx = 0.0;
  double _pendingMoveDy = 0.0;
  bool _isMoveScheduled = false;

  @override
  void sendMove(double dx, double dy) {
    _pendingMoveDx += dx;
    _pendingMoveDy += dy;

    if (!_isMoveScheduled) {
      _isMoveScheduled = true;
      scheduleMicrotask(_flushMove);
    }
  }

  @override
  void sendAbsMove(double x, double y) {}

  void _flushMove() {
    _isMoveScheduled = false;
    final dx = _pendingMoveDx;
    final dy = _pendingMoveDy;
    _pendingMoveDx = 0.0;
    _pendingMoveDy = 0.0;

    if (dx != 0 || dy != 0) {
      sendEvent({
        'event': 'MOVE',
        'dx': dx,
        'dy': dy,
        't': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  @override
  void sendLeftClick() {
    sendEvent({'event': 'LEFT_CLICK'});
  }

  @override
  void sendRightClick() {
    sendEvent({'event': 'RIGHT_CLICK'});
  }

  @override
  void sendDoubleClick() {
    sendEvent({'event': 'DOUBLE_CLICK'});
  }

  @override
  void sendButtonDown([String button = 'left']) {
    if (button == 'right') {
      _isRightButtonDown = true;
    } else {
      _isLeftButtonDown = true;
    }
    sendEvent({
      'event': 'BUTTON_DOWN',
      'button': button,
    });
  }

  @override
  void sendButtonUp([String button = 'left']) {
    if (button == 'right') {
      _isRightButtonDown = false;
    } else {
      _isLeftButtonDown = false;
    }
    sendEvent({
      'event': 'BUTTON_UP',
      'button': button,
    });
  }

  @override
  void sendScroll(double dx, double dy) {
    sendEvent({
      'event': 'SCROLL',
      'dx': dx,
      'dy': dy,
    });
  }

  @override
  void sendTextInput(String text) {
    sendEvent({
      'event': 'TEXT_INPUT',
      'text': text,
    });
  }

  @override
  void sendKeyPress(String key) {
    sendEvent({
      'event': 'KEY_PRESS',
      'key': key,
    });
  }

  @override
  void sendKeyDown(String key) {
    _heldKeys.add(key);
    sendEvent({
      'event': 'KEY_DOWN',
      'key': key,
    });
  }

  @override
  void sendKeyUp(String key) {
    _heldKeys.remove(key);
    sendEvent({
      'event': 'KEY_UP',
      'key': key,
    });
  }

  @override
  void sendTwoFingerBrowserBack() {
    sendEvent({'event': 'TWO_FINGER_BROWSER_BACK'});
  }

  @override
  void sendTwoFingerBrowserForward() {
    sendEvent({'event': 'TWO_FINGER_BROWSER_FORWARD'});
  }

  @override
  void sendThreeFingerUp() {
    sendEvent({'event': 'THREE_FINGER_UP'});
  }

  @override
  void sendThreeFingerDown() {
    sendEvent({'event': 'THREE_FINGER_DOWN'});
  }

  @override
  void sendThreeFingerLeft() {
    sendEvent({'event': 'THREE_FINGER_LEFT'});
  }

  @override
  void sendThreeFingerRight() {
    sendEvent({'event': 'THREE_FINGER_RIGHT'});
  }

  @override
  void sendFourFingerLeft() {
    sendEvent({'event': 'FOUR_FINGER_LEFT'});
  }

  @override
  void sendFourFingerRight() {
    sendEvent({'event': 'FOUR_FINGER_RIGHT'});
  }

  @override
  void sendSystemMagnify(double scale) {
    if (_status != ConnectionStatus.connected) return;
    sendEvent({
      'event': 'SYSTEM_MAGNIFY',
      'scale': scale,
    });
  }

  @override
  void sendVolumeUp() => sendEvent({'event': 'VOLUME_UP'});

  @override
  void sendVolumeDown() => sendEvent({'event': 'VOLUME_DOWN'});

  @override
  void sendVolumeMute() => sendEvent({'event': 'VOLUME_MUTE'});

  @override
  void sendBrightnessUp() => sendEvent({'event': 'BRIGHTNESS_UP'});

  @override
  void sendBrightnessDown() => sendEvent({'event': 'BRIGHTNESS_DOWN'});

  @override
  void sendWindowsSearch() => sendEvent({'event': 'WINDOWS_SEARCH'});

  @override
  void sendTaskbarApps() => sendEvent({'event': 'TASKBAR_APPS'});

  @override
  void releaseAll() {
    if (_isLeftButtonDown) {
      sendButtonUp('left');
    }
    if (_isRightButtonDown) {
      sendButtonUp('right');
    }
    for (final key in _heldKeys.toList()) {
      sendKeyUp(key);
    }
    _heldKeys.clear();
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    statusNotifier.value = newStatus;
  }

  void dispose() {
    _statusSubscription?.cancel();
    pendingTrustPcNotifier.dispose();
    trustService.dispose();
    statusNotifier.dispose();
    errorNotifier.dispose();
    userMessageNotifier.dispose();
    targetDeviceNotifier.dispose();
  }
}
