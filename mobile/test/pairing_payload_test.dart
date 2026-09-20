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
  });
}
