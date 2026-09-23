import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/touchpad_source.dart';
import 'package:mobile/src/websocket_service.dart';

void main() {
  group('TouchpadSource Tests', () {
    test('initial state and properties', () {
      final wsService = WebSocketService();
      final source = TouchpadSource(wsService);

      expect(source.mode, MouseMode.touchpad);
      expect(source.displayName, 'Touchpad');
      expect(source.isActive, isFalse);
      expect(source.wsService, wsService);
    });

    test('activation lifecycle callbacks toggle isActive', () {
      final wsService = WebSocketService();
      final source = TouchpadSource(wsService);

      source.activate();
      expect(source.isActive, isTrue);

      source.deactivate();
      expect(source.isActive, isFalse);
    });
  });
}
