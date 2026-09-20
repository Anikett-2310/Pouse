import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/websocket_service.dart';

void main() {
  group('Reconnection and MOVE Event Tests', () {
    test('sendMove does not throw and works across lifecycle states', () async {
      final service = WebSocketService();
      
      // Before connect
      expect(service.status, ConnectionStatus.disconnected);
      service.sendMove(10.0, 5.0); // Should be safely ignored when disconnected

      // Disconnect reset
      service.disconnect();
      expect(service.status, ConnectionStatus.disconnected);

      // Verify status transitions
      final connectFuture = service.connect('127.0.0.1', port: 8081);
      expect(service.status, ConnectionStatus.connecting);

      await connectFuture; // Will fail/timeout or error cleanly
      expect(service.status, ConnectionStatus.error);

      // Retry disconnect reset
      service.disconnect();
      expect(service.status, ConnectionStatus.disconnected);
    });
  });
}
