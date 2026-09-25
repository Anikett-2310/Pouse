import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/transports/bluetooth_hid_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bluetooth HID Mouse & Keyboard Unit Tests', () {
    late BluetoothHidService btService;

    setUp(() {
      btService = BluetoothHidService();
    });

    test('Bluetooth HID initial state is disconnected', () {
      expect(btService.isConnected, isFalse);
    });

    test('ASCII Character to Keycode mapping', () {
      // Lowercase letters
      expect(btService.getHidKeycodeForChar('a'), equals(0x04));
      expect(btService.getHidKeycodeForChar('b'), equals(0x05));
      expect(btService.getHidKeycodeForChar('z'), equals(0x1D));

      // Uppercase letters
      expect(btService.getHidKeycodeForChar('A'), equals(0x04));
      expect(btService.getHidKeycodeForChar('Z'), equals(0x1D));

      // Digits
      expect(btService.getHidKeycodeForChar('1'), equals(0x1E));
      expect(btService.getHidKeycodeForChar('9'), equals(0x26));
      expect(btService.getHidKeycodeForChar('0'), equals(0x27));

      // Formatting
      expect(btService.getHidKeycodeForChar(' '), equals(0x2C));
      expect(btService.getHidKeycodeForChar('\n'), equals(0x28));
    });

    test('Special Key Name to Keycode mapping', () {
      expect(btService.getHidKeycodeForKeyName('backspace'), equals(0x2A));
      expect(btService.getHidKeycodeForKeyName('enter'), equals(0x28));
      expect(btService.getHidKeycodeForKeyName('escape'), equals(0x29));
      expect(btService.getHidKeycodeForKeyName('arrow_up'), equals(0x52));
      expect(btService.getHidKeycodeForKeyName('arrow_down'), equals(0x51));
      expect(btService.getHidKeycodeForKeyName('arrow_left'), equals(0x50));
      expect(btService.getHidKeycodeForKeyName('arrow_right'), equals(0x4F));
      expect(btService.getHidKeycodeForKeyName('w'), equals(0x1A));
      expect(btService.getHidKeycodeForKeyName('a'), equals(0x04));
      expect(btService.getHidKeycodeForKeyName('s'), equals(0x16));
      expect(btService.getHidKeycodeForKeyName('d'), equals(0x07));
    });

    test('Release all active held state cleans up safely', () {
      btService.releaseAll();
      expect(btService.isConnected, isFalse);
    });
  });
}
