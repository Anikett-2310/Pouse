import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/transports/bluetooth_rfcomm_test_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bluetooth RFCOMM Test Service Unit Tests', () {
    late BluetoothRfcommTestService service;

    setUp(() {
      service = BluetoothRfcommTestService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Initial status is stopped', () {
      expect(service.statusNotifier.value, equals('stopped'));
    });
  });
}
