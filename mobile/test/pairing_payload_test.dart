import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/pairing_payload.dart';

void main() {
  group('PairingPayload Parsing and Validation Tests', () {
    test('parses valid Pouse pairing payload JSON correctly', () {
      const validJson = '''
      {
        "type": "pouse_pair",
        "version": 1,
        "name": "Aniket PC",
        "host": "192.168.1.150",
        "port": 8081
      }
      ''';

      final payload = PairingPayload.parse(validJson);
      expect(payload, isNotNull);
      expect(payload!.type, 'pouse_pair');
      expect(payload.version, 1);
      expect(payload.name, 'Aniket PC');
      expect(payload.host, '192.168.1.150');
      expect(payload.port, 8081);
      expect(payload.pairToken, isNull);
      expect(payload.supportsScreen, isFalse);
    });

    test('rejects payload with invalid type', () {
      const invalidTypeJson = '''
      {
        "type": "malicious_payload",
        "version": 1,
        "name": "PC",
        "host": "192.168.1.150",
        "port": 8081
      }
      ''';

      final payload = PairingPayload.parse(invalidTypeJson);
      expect(payload, isNull);
    });

    test('rejects payload with unsupported version', () {
      const invalidVersionJson = '''
      {
        "type": "pouse_pair",
        "version": 99,
        "name": "PC",
        "host": "192.168.1.150",
        "port": 8081
      }
      ''';

      final payload = PairingPayload.parse(invalidVersionJson);
      expect(payload, isNull);
    });

    test('rejects payload with non-IPv4 host string or URL', () {
      const urlHostJson = '''
      {
        "type": "pouse_pair",
        "version": 1,
        "name": "PC",
        "host": "http://example.com/malicious",
        "port": 8081
      }
      ''';

      final payload = PairingPayload.parse(urlHostJson);
      expect(payload, isNull);
    });

    test('rejects payload with invalid port numbers', () {
      const invalidPortJson = '''
      {
        "type": "pouse_pair",
        "version": 1,
        "name": "PC",
        "host": "192.168.1.100",
        "port": 70000
      }
      ''';

      final payload = PairingPayload.parse(invalidPortJson);
      expect(payload, isNull);
    });

    test('Parses new Remote Screen QR payload with pairToken and capabilities', () {
      const newJson = '{"type":"pouse_pair","version":1,"name":"Pouse PC","host":"192.168.1.100","port":8081,"protocolVersion":1,"pairToken":"4f9a1c8b3e2d6f0a5c7b9e1d3f5a7c9b","capabilities":["touchpad","motion","touchless","screen"]}';
      final payload = PairingPayload.parse(newJson);
      expect(payload, isNotNull);
      expect(payload!.name, 'Pouse PC');
      expect(payload.host, '192.168.1.100');
      expect(payload.port, 8081);
      expect(payload.pairToken, '4f9a1c8b3e2d6f0a5c7b9e1d3f5a7c9b');
      expect(payload.protocolVersion, 1);
      expect(payload.supportsScreen, isTrue);
    });
  });
}
