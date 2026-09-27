import 'dart:convert';

class PairingPayload {
  final String type;
  final int version;
  final String name;
  final String host;
  final int port;
  final int protocolVersion;
  final String? pairToken;
  final List<String> capabilities;

  PairingPayload({
    required this.type,
    required this.version,
    required this.name,
    required this.host,
    required this.port,
    this.protocolVersion = 1,
    this.pairToken,
    this.capabilities = const ['touchpad', 'motion', 'touchless'],
  });

  bool get supportsScreen => capabilities.contains('screen');

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
      final protocolVersion = (map['protocolVersion'] as int?) ?? 1;
      final pairToken = map['pairToken'] as String?;

      List<String> capabilities = const ['touchpad', 'motion', 'touchless'];
      if (map['capabilities'] is List) {
        capabilities = (map['capabilities'] as List).map((e) => e.toString()).toList();
      }

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
        protocolVersion: protocolVersion,
        pairToken: pairToken,
        capabilities: capabilities,
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
      'protocolVersion': protocolVersion,
      if (pairToken != null) 'pairToken': pairToken,
      'capabilities': capabilities,
    };
  }
}
