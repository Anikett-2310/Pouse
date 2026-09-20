import 'dart:convert';

class PairingPayload {
  final String type;
  final int version;
  final String name;
  final String host;
  final int port;

  PairingPayload({
    required this.type,
    required this.version,
    required this.name,
    required this.host,
    required this.port,
  });

  static PairingPayload? parse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      if (map['type'] != 'pouse_pair') return null;
      if (map['version'] != 1) return null;

      final host = map['host'];
      final port = map['port'];
      final name = (map['name'] as String?) ?? 'Pouse PC';

      if (host is! String || port is! int) return null;

      final trimmedHost = host.trim();
      try {
        Uri.parseIPv4Address(trimmedHost);
      } catch (_) {
        return null;
      }

      if (port <= 0 || port > 65535) return null;

      return PairingPayload(
        type: map['type'] as String,
        version: map['version'] as int,
        name: name,
        host: trimmedHost,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'version': version,
      'name': name,
      'host': host,
      'port': port,
    };
  }
}
