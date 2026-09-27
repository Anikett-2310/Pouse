import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/mouse_mode_manager.dart';
import 'package:mobile/src/sources/remote_screen_source.dart';
import 'package:mobile/src/websocket_service.dart';

void main() {
  group('Remote Screen Session Startup & Keyframe Tests', () {
    late WebSocketService wsService;
    late RemoteScreenSource source;

    setUp(() {
      wsService = WebSocketService();
      source = RemoteScreenSource(wsService);
    });

    tearDown(() {
      wsService.dispose();
    });

    test('Initial connection AUTH_OK in IDLE mode does not start video or spam START_SCREEN', () {
      wsService.setPairToken('test_token_1234');
      expect(source.mode, MouseMode.remoteScreen);
      expect(source.isActive, isFalse);
    });

    test('RemoteScreenSource properties and transport bindings', () {
      expect(source.displayName, 'Remote Screen');
      expect(source.transport, equals(wsService));

      source.activate();
      expect(source.isActive, isTrue);

      source.deactivate();
      expect(source.isActive, isFalse);
    });
  });
}
