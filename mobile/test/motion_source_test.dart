import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/motion_source.dart';
import 'package:mobile/src/websocket_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockWebSocketService extends WebSocketService {
  final List<Map<String, dynamic>> sentEvents = [];

  @override
  ConnectionStatus get status => ConnectionStatus.connected;

  @override
  void sendEvent(Map<String, dynamic> event) {
    sentEvents.add(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionSource Unit Tests', () {
    late MockWebSocketService mockWsService;
    late MotionSource source;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockWsService = MockWebSocketService();
      source = MotionSource(
        mockWsService,
        accelStream: const Stream<AccelerometerEvent>.empty(),
        gyroStream: const Stream<GyroscopeEvent>.empty(),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('initial state defaults correctly', () {
      expect(source.mode, equals(MouseMode.motion));
      expect(source.displayName, equals('Motion'));
      expect(source.isActive, isFalse);
      expect(source.isTracking, isFalse);
      expect(source.isSettling, isFalse);
      expect(source.sensitivity, equals(MotionSource.defaultSensitivity));
    });

    test('activate and deactivate toggle isActive state', () {
      source.activate();
      expect(source.isActive, isTrue);

      source.deactivate();
      expect(source.isActive, isFalse);
    });

    test('startTracking initiates 120ms settling period', () async {
      source.activate();
      source.startTracking();

      // Immediately after startTracking, isSettling is true and isTracking is false
      expect(source.isSettling, isTrue);
      expect(source.isTracking, isFalse);

      // Wait 150ms for settling timer to complete
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(source.isSettling, isFalse);
      expect(source.isTracking, isTrue);

      source.stopTracking();
      expect(source.isTracking, isFalse);
      expect(source.isSettling, isFalse);
    });

    test('deactivate stops tracking immediately', () async {
      source.activate();
      source.startTracking();
      expect(source.isSettling, isTrue);

      source.deactivate();
      expect(source.isActive, isFalse);
      expect(source.isTracking, isFalse);
      expect(source.isSettling, isFalse);
    });

    test('setSensitivity updates value and saveSensitivity persists to SharedPreferences', () async {
      source.setSensitivity(35.0);
      expect(source.sensitivity, equals(35.0));

      await source.saveSensitivity(35.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(MotionSource.prefSensitivityKey), equals(35.0));
    });

    test('Motion vertical direction pitch up results in dy < 0 (cursor UP) and pitch down results in dy > 0 (cursor DOWN)', () async {
      final accelController = StreamController<AccelerometerEvent>.broadcast();
      final gyroController = StreamController<GyroscopeEvent>.broadcast();

      final motion = MotionSource(
        mockWsService,
        accelStream: accelController.stream,
        gyroStream: gyroController.stream,
      );

      motion.activate();
      motion.startTracking();

      // Wait 150ms for settling phase to end
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Feed gravity vector samples so low-pass EMA filter converges to (0.0, 8.0, 5.6)
      for (int i = 0; i < 20; i++) {
        accelController.add(AccelerometerEvent(0.0, 8.0, 5.6, DateTime.now()));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 1st gyro sample to establish timestamp
      gyroController.add(GyroscopeEvent(0.0, 0.0, 0.0, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      mockWsService.sentEvents.clear();

      // Feed pitch UP gyro event (wx = +1.0 rad/s tilting phone top edge up)
      gyroController.add(GyroscopeEvent(1.0, 0.0, 0.0, DateTime.now()));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final moveEvents = mockWsService.sentEvents.where((e) => e['event'] == 'MOVE').toList();
      expect(moveEvents.isNotEmpty, isTrue);
      final double dy = moveEvents.first['dy'];
      expect(dy < 0, isTrue); // Phone UP -> dy < 0 (Cursor UP on Windows)

      await accelController.close();
      await gyroController.close();
      motion.deactivate();
    });
  });
}
