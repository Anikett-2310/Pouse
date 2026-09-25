import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/transports/bluetooth_hid_service.dart';
import 'package:mobile/src/transports/pouse_transport.dart';
import 'package:mobile/src/transports/transport_manager.dart';
import 'package:mobile/src/websocket_service.dart';

class MockPouseTransport implements PouseTransport {
  final List<String> log = [];
  bool connected = true;

  @override
  TransportType get type => TransportType.wifi;

  @override
  ConnectionStatus get status => connected ? ConnectionStatus.connected : ConnectionStatus.disconnected;

  @override
  ValueNotifier<ConnectionStatus> get statusNotifier => ValueNotifier<ConnectionStatus>(status);

  @override
  bool get isConnected => connected;

  @override
  void sendMove(double dx, double dy) => log.add('move:$dx,$dy');

  @override
  void sendLeftClick() => log.add('leftClick');

  @override
  void sendRightClick() => log.add('rightClick');

  @override
  void sendDoubleClick() => log.add('doubleClick');

  @override
  void sendButtonDown([String button = 'left']) => log.add('buttonDown:$button');

  @override
  void sendButtonUp([String button = 'left']) => log.add('buttonUp:$button');

  @override
  void sendScroll(double dx, double dy) => log.add('scroll:$dx,$dy');

  @override
  void sendTextInput(String text) => log.add('text:$text');

  @override
  void sendKeyPress(String key) => log.add('keyPress:$key');

  @override
  void sendKeyDown(String key) => log.add('keyDown:$key');

  @override
  void sendKeyUp(String key) => log.add('keyUp:$key');

  @override
  void sendTwoFingerBrowserBack() => log.add('browserBack');

  @override
  void sendTwoFingerBrowserForward() => log.add('browserForward');

  @override
  void sendThreeFingerUp() => log.add('taskView');

  @override
  void sendThreeFingerDown() => log.add('showDesktop');

  @override
  void sendThreeFingerLeft() => log.add('prevApp');

  @override
  void sendThreeFingerRight() => log.add('nextApp');

  @override
  void sendFourFingerLeft() => log.add('prevDesktop');

  @override
  void sendFourFingerRight() => log.add('nextDesktop');

  @override
  void releaseAll() => log.add('releaseAll');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PouseTransport Architecture Tests', () {
    test('WebSocketService implements PouseTransport', () {
      final ws = WebSocketService();
      expect(ws, isA<PouseTransport>());
    });

    test('BluetoothHidService implements PouseTransport', () {
      final bt = BluetoothHidService();
      expect(bt, isA<PouseTransport>());
    });

    test('TouchpadSource is transport-agnostic', () {
      final mock = MockPouseTransport();
      final source = TouchpadSource(mock);

      expect(source.transport, equals(mock));
      source.transport.sendMove(10, 20);
      expect(mock.log, contains('move:10.0,20.0'));
    });

    test('MotionSource is transport-agnostic', () {
      final mock = MockPouseTransport();
      final source = MotionSource(mock);

      expect(source.transport, equals(mock));
      source.sendLeftClick();
      expect(mock.log, contains('leftClick'));
    });
  });

  group('TransportManager Tests', () {
    test('Exactly one transport is active by default (Wi-Fi)', () {
      final ws = WebSocketService();
      final bt = BluetoothHidService();
      final manager = TransportManager(wifiTransport: ws, bluetoothTransport: bt);

      expect(manager.activeType, equals(TransportType.wifi));
      expect(manager.activeTransport, equals(ws));
    });

    test('Failed replacement transport does NOT destroy current working transport', () async {
      final ws = WebSocketService();
      final bt = BluetoothHidService();
      final manager = TransportManager(wifiTransport: ws, bluetoothTransport: bt);

      // Bluetooth is not connected, so switching should fail gracefully without altering active transport
      final success = await manager.switchTransport(TransportType.bluetooth, btAddress: '00:11:22:33:44:55');
      expect(success, isFalse);
      expect(manager.activeType, equals(TransportType.wifi));
      expect(manager.activeTransport, equals(ws));
    });
  });

  group('Bluetooth HID Keyboard & Action Encodings', () {
    test('ASCII Keycode translation verification', () {
      final bt = BluetoothHidService();
      expect(bt.getHidKeycodeForChar('a'), equals(0x04)); // HID usage 'a'
      expect(bt.getHidKeycodeForChar('z'), equals(0x1D)); // HID usage 'z'
      expect(bt.getHidKeycodeForChar('1'), equals(0x1E)); // HID usage '1'
      expect(bt.getHidKeycodeForChar('0'), equals(0x27)); // HID usage '0'
      expect(bt.getHidKeycodeForChar(' '), equals(0x2C)); // Space
      expect(bt.getHidKeycodeForChar('\n'), equals(0x28)); // Enter
    });

    test('Named key press mapping', () {
      final bt = BluetoothHidService();
      expect(bt.getHidKeycodeForKeyName('backspace'), equals(0x2A));
      expect(bt.getHidKeycodeForKeyName('enter'), equals(0x28));
      expect(bt.getHidKeycodeForKeyName('escape'), equals(0x29));
      expect(bt.getHidKeycodeForKeyName('arrow_up'), equals(0x52));
      expect(bt.getHidKeycodeForKeyName('w'), equals(0x1A));
    });
  });
}
