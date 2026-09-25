import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../websocket_service.dart';
import 'pouse_transport.dart';

/// Bluetooth HID Transport implementation using native Android BluetoothHidDevice API.
class BluetoothHidService implements PouseTransport {
  static const MethodChannel _controlChannel = MethodChannel('pouse/bluetooth_control');
  static const EventChannel _statusChannel = EventChannel('pouse/bluetooth_status');

  ConnectionStatus _status = ConnectionStatus.disconnected;

  @override
  final ValueNotifier<ConnectionStatus> statusNotifier =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.disconnected);
  final ValueNotifier<String?> errorNotifier = ValueNotifier<String?>(null);

  int _heldButtonsMask = 0;
  final Set<int> _heldKeycodes = <int>{};
  int _heldModifiers = 0;
  StreamSubscription? _statusSubscription;

  BluetoothHidService() {
    _listenToStatusEvents();
  }

  @override
  TransportType get type => TransportType.bluetooth;

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  void _listenToStatusEvents() {
    _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          switch (event) {
            case 'connected':
              _setStatus(ConnectionStatus.connected);
              break;
            case 'connecting':
              _setStatus(ConnectionStatus.connecting);
              break;
            case 'disconnected':
              _setStatus(ConnectionStatus.disconnected);
              break;
            case 'error':
              _setStatus(ConnectionStatus.error);
              break;
          }
        }
      },
      onError: (_) {
        _setStatus(ConnectionStatus.error);
      },
    );
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    statusNotifier.value = newStatus;
  }

  Future<bool> isSupported() async {
    try {
      final bool? supported = await _controlChannel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final bool? granted = await _controlChannel.invokeMethod<bool>('requestPermissions');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, String>>> getPairedDevices() async {
    try {
      final List<dynamic>? rawList = await _controlChannel.invokeMethod<List<dynamic>>('getPairedDevices');
      if (rawList == null) return [];
      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'name': (map['name'] as String?) ?? 'Unknown Device',
          'address': (map['address'] as String?) ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String address) async {
    return connectDevice(address);
  }

  Future<bool> connectDevice(String address) async {
    try {
      _setStatus(ConnectionStatus.connecting);
      errorNotifier.value = null;
      final bool? result = await _controlChannel.invokeMethod<bool>('connect', {'address': address});
      if (result != true) {
        _setStatus(ConnectionStatus.disconnected);
        errorNotifier.value = 'Failed to connect to Bluetooth HID host at $address';
        return false;
      }
      return true;
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      errorNotifier.value = 'Bluetooth HID connection error: $e';
      return false;
    }
  }

  Future<void> disconnect() async {
    await disconnectDevice();
  }

  Future<void> disconnectDevice() async {
    try {
      releaseAll();
      await _controlChannel.invokeMethod('disconnect');
      _setStatus(ConnectionStatus.disconnected);
    } catch (_) {}
  }

  @override
  void sendMove(double dx, double dy) {
    if (_status != ConnectionStatus.connected) return;
    _controlChannel.invokeMethod('sendMouseReport', {
      'button': _heldButtonsMask,
      'dx': dx.round(),
      'dy': dy.round(),
      'wheel': 0,
    });
  }

  @override
  void sendLeftClick() {
    if (_status != ConnectionStatus.connected) return;
    _controlChannel.invokeMethod('sendMouseReport', {'button': 0x01, 'dx': 0, 'dy': 0, 'wheel': 0});
    _controlChannel.invokeMethod('sendMouseReport', {'button': 0x00, 'dx': 0, 'dy': 0, 'wheel': 0});
  }

  @override
  void sendRightClick() {
    if (_status != ConnectionStatus.connected) return;
    _controlChannel.invokeMethod('sendMouseReport', {'button': 0x02, 'dx': 0, 'dy': 0, 'wheel': 0});
    _controlChannel.invokeMethod('sendMouseReport', {'button': 0x00, 'dx': 0, 'dy': 0, 'wheel': 0});
  }

  @override
  void sendDoubleClick() {
    sendLeftClick();
    sendLeftClick();
  }

  @override
  void sendButtonDown([String button = 'left']) {
    if (_status != ConnectionStatus.connected) return;
    if (button == 'right') {
      _heldButtonsMask |= 0x02;
    } else {
      _heldButtonsMask |= 0x01;
    }
    _controlChannel.invokeMethod('sendMouseReport', {'button': _heldButtonsMask, 'dx': 0, 'dy': 0, 'wheel': 0});
  }

  @override
  void sendButtonUp([String button = 'left']) {
    if (_status != ConnectionStatus.connected) return;
    if (button == 'right') {
      _heldButtonsMask &= ~0x02;
    } else {
      _heldButtonsMask &= ~0x01;
    }
    _controlChannel.invokeMethod('sendMouseReport', {'button': _heldButtonsMask, 'dx': 0, 'dy': 0, 'wheel': 0});
  }

  @override
  void sendScroll(double dx, double dy) {
    if (_status != ConnectionStatus.connected) return;
    _controlChannel.invokeMethod('sendMouseReport', {
      'button': _heldButtonsMask,
      'dx': 0,
      'dy': 0,
      'wheel': dy.round(),
    });
  }

  @override
  void sendTextInput(String text) {
    if (_status != ConnectionStatus.connected) return;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final mapping = _charToHidKeycode(char);
      if (mapping != null) {
        _sendKeyboardReport(mapping.modifier, [mapping.keycode]);
        _sendKeyboardReport(0, []);
      }
    }
  }

  @override
  void sendKeyPress(String key) {
    if (_status != ConnectionStatus.connected) return;
    final mapping = _keyNameToHidKeycode(key);
    if (mapping != null) {
      _sendKeyboardReport(mapping.modifier, [mapping.keycode]);
      _sendKeyboardReport(0, []);
    }
  }

  @override
  void sendKeyDown(String key) {
    if (_status != ConnectionStatus.connected) return;
    final mapping = _keyNameToHidKeycode(key);
    if (mapping != null) {
      _heldModifiers |= mapping.modifier;
      _heldKeycodes.add(mapping.keycode);
      _sendKeyboardReport(_heldModifiers, _heldKeycodes.toList());
    }
  }

  @override
  void sendKeyUp(String key) {
    if (_status != ConnectionStatus.connected) return;
    final mapping = _keyNameToHidKeycode(key);
    if (mapping != null) {
      _heldKeycodes.remove(mapping.keycode);
      if (!_heldKeycodes.any((k) => (k & mapping.modifier) != 0)) {
        _heldModifiers &= ~mapping.modifier;
      }
      _sendKeyboardReport(_heldModifiers, _heldKeycodes.toList());
    }
  }

  @override
  void sendTwoFingerBrowserBack() {
    // Alt + Left Arrow (Alt = 0x04, Left = 0x50)
    _sendKeyboardReport(0x04, [0x50]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendTwoFingerBrowserForward() {
    // Alt + Right Arrow (Alt = 0x04, Right = 0x4F)
    _sendKeyboardReport(0x04, [0x4F]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendThreeFingerUp() {
    // Win + Tab (Win = 0x08, Tab = 0x2B)
    _sendKeyboardReport(0x08, [0x2B]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendThreeFingerDown() {
    // Win + D (Win = 0x08, 'd' = 0x07)
    _sendKeyboardReport(0x08, [0x07]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendThreeFingerLeft() {
    // Alt + Shift + Tab (Alt=0x04, Shift=0x02 -> 0x06, Tab=0x2B)
    _sendKeyboardReport(0x06, [0x2B]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendThreeFingerRight() {
    // Alt + Tab (Alt = 0x04, Tab = 0x2B)
    _sendKeyboardReport(0x04, [0x2B]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendFourFingerLeft() {
    // Win + Ctrl + Left (Win=0x08, Ctrl=0x01 -> 0x09, Left=0x50)
    _sendKeyboardReport(0x09, [0x50]);
    _sendKeyboardReport(0, []);
  }

  @override
  void sendFourFingerRight() {
    // Win + Ctrl + Right (Win=0x08, Ctrl=0x01 -> 0x09, Right=0x4F)
    _sendKeyboardReport(0x09, [0x4F]);
    _sendKeyboardReport(0, []);
  }

  @override
  void releaseAll() {
    _heldButtonsMask = 0;
    _heldKeycodes.clear();
    _heldModifiers = 0;
    if (_status == ConnectionStatus.connected) {
      _controlChannel.invokeMethod('releaseAll');
    }
  }

  int? getHidKeycodeForChar(String char) => _charToHidKeycode(char)?.keycode;
  int? getHidKeycodeForKeyName(String name) => _keyNameToHidKeycode(name)?.keycode;

  void _sendKeyboardReport(int modifiers, List<int> keycodes) {
    _controlChannel.invokeMethod('sendKeyboardReport', {
      'modifiers': modifiers,
      'keycodes': keycodes,
    });
  }

  void dispose() {
    _statusSubscription?.cancel();
    statusNotifier.dispose();
    errorNotifier.dispose();
    releaseAll();
  }
}

class _HidKeyMapping {
  final int modifier;
  final int keycode;
  const _HidKeyMapping(this.keycode, [this.modifier = 0]);
}

_HidKeyMapping? _keyNameToHidKeycode(String key) {
  switch (key.toLowerCase()) {
    case 'w':
      return const _HidKeyMapping(0x1A);
    case 'a':
      return const _HidKeyMapping(0x04);
    case 's':
      return const _HidKeyMapping(0x16);
    case 'd':
      return const _HidKeyMapping(0x07);
    case 'arrow_up':
    case 'up':
      return const _HidKeyMapping(0x52);
    case 'arrow_down':
    case 'down':
      return const _HidKeyMapping(0x51);
    case 'arrow_left':
    case 'left':
      return const _HidKeyMapping(0x50);
    case 'arrow_right':
    case 'right':
      return const _HidKeyMapping(0x4F);
    case 'enter':
    case 'return':
      return const _HidKeyMapping(0x28);
    case 'backspace':
      return const _HidKeyMapping(0x2A);
    case 'space':
      return const _HidKeyMapping(0x2C);
    case 'tab':
      return const _HidKeyMapping(0x2B);
    case 'escape':
      return const _HidKeyMapping(0x29);
    default:
      if (key.length == 1) {
        return _charToHidKeycode(key);
      }
      return null;
  }
}

_HidKeyMapping? _charToHidKeycode(String char) {
  if (char.isEmpty) return null;
  final code = char.codeUnitAt(0);

  // Lowercase a-z (0x04 to 0x1D)
  if (code >= 97 && code <= 122) {
    return _HidKeyMapping(0x04 + (code - 97));
  }
  // Uppercase A-Z (0x04 to 0x1D with Shift 0x02)
  if (code >= 65 && code <= 90) {
    return _HidKeyMapping(0x04 + (code - 65), 0x02);
  }
  // Digits 1-9 (0x1E to 0x26), 0 (0x27)
  if (code >= 49 && code <= 57) {
    return _HidKeyMapping(0x1E + (code - 49));
  }
  if (code == 48) {
    return const _HidKeyMapping(0x27);
  }

  // Common ASCII Punctuation
  switch (char) {
    case ' ':
      return const _HidKeyMapping(0x2C);
    case '\n':
    case '\r':
      return const _HidKeyMapping(0x28);
    case '.':
      return const _HidKeyMapping(0x37);
    case ',':
      return const _HidKeyMapping(0x36);
    case '-':
      return const _HidKeyMapping(0x2D);
    case '=':
      return const _HidKeyMapping(0x2E);
    case '/':
      return const _HidKeyMapping(0x38);
    case ';':
      return const _HidKeyMapping(0x33);
    case '\'':
      return const _HidKeyMapping(0x34);
    case '!':
      return const _HidKeyMapping(0x1E, 0x02);
    case '@':
      return const _HidKeyMapping(0x1F, 0x02);
    case '#':
      return const _HidKeyMapping(0x20, 0x02);
    case '\$':
      return const _HidKeyMapping(0x21, 0x02);
    case '%':
      return const _HidKeyMapping(0x22, 0x02);
    case '^':
      return const _HidKeyMapping(0x23, 0x02);
    case '&':
      return const _HidKeyMapping(0x24, 0x02);
    case '*':
      return const _HidKeyMapping(0x25, 0x02);
    case '(':
      return const _HidKeyMapping(0x26, 0x02);
    case ')':
      return const _HidKeyMapping(0x27, 0x02);
    default:
      return null;
  }
}
