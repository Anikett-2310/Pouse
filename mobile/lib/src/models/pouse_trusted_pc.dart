/// Model representing a trusted Pouse PC for application-level Trust On First Use (TOFU).
class PouseTrustedPc {
  final String id;
  final String name;
  final String classicAddress;
  final DateTime firstTrustedAt;
  final DateTime lastSeenAt;

  const PouseTrustedPc({
    required this.id,
    required this.name,
    required this.classicAddress,
    required this.firstTrustedAt,
    required this.lastSeenAt,
  });

  PouseTrustedPc copyWith({
    String? id,
    String? name,
    String? classicAddress,
    DateTime? firstTrustedAt,
    DateTime? lastSeenAt,
  }) {
    return PouseTrustedPc(
      id: id ?? this.id,
      name: name ?? this.name,
      classicAddress: classicAddress ?? this.classicAddress,
      firstTrustedAt: firstTrustedAt ?? this.firstTrustedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'classicAddress': classicAddress,
    'firstTrustedAt': firstTrustedAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
  };

  factory PouseTrustedPc.fromJson(Map<String, dynamic> json) => PouseTrustedPc(
    id: json['id'] as String? ?? json['classicAddress'] as String? ?? '',
    name: json['name'] as String? ?? 'Pouse PC',
    classicAddress: json['classicAddress'] as String? ?? '',
    firstTrustedAt: DateTime.tryParse(json['firstTrustedAt'] as String? ?? '') ?? DateTime.now(),
    lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PouseTrustedPc &&
          runtimeType == other.runtimeType &&
          (id == other.id || classicAddress == other.classicAddress);

  @override
  int get hashCode => id.hashCode ^ classicAddress.hashCode;

  @override
  String toString() =>
      'PouseTrustedPc(id: $id, name: $name, classic: $classicAddress, trustedAt: $firstTrustedAt)';
}
