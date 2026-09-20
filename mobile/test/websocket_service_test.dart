import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/websocket_service.dart';

void main() {
  group('WebSocketService Tests', () {
    test('initial state is disconnected', () {
      final service = WebSocketService();
      expect(service.status, ConnectionStatus.disconnected);
      expect(service.statusNotifier.value, ConnectionStatus.disconnected);
      expect(service.errorNotifier.value, null);
    });

    test('connect transitions to connecting then times out on invalid IP', () async {
      final service = WebSocketService();
      
      // Attempt connect to unroutable IP
      final connectFuture = service.connect('10.255.255.1', port: 8081);
      
      expect(service.status, ConnectionStatus.connecting);
      expect(service.statusNotifier.value, ConnectionStatus.connecting);

      await connectFuture;

      expect(service.status, ConnectionStatus.error);
      expect(service.statusNotifier.value, ConnectionStatus.error);
      expect(service.errorNotifier.value, contains('Connection timed out'));
    });
  });
}
