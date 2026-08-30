class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.addedAt,
    required this.lastSeenAt,
    this.revokedAt,
  });

  final String id;
  final String name;
  final String platform;
  final String publicKey;
  final DateTime addedAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  TrustedDevice copyWith({
    String? name,
    DateTime? lastSeenAt,
    DateTime? revokedAt,
  }) => TrustedDevice(
    id: id,
    name: name ?? this.name,
    platform: platform,
    publicKey: publicKey,
    addedAt: addedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    revokedAt: revokedAt ?? this.revokedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'publicKey': publicKey,
    'addedAt': addedAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    if (revokedAt case final value?)
      'revokedAt': value.toUtc().toIso8601String(),
  };

  factory TrustedDevice.fromJson(Map<String, Object?> json) => TrustedDevice(
    id: json['id']! as String,
    name: json['name']! as String,
    platform: json['platform']! as String,
    publicKey: json['publicKey']! as String,
    addedAt: DateTime.parse(json['addedAt']! as String).toUtc(),
    lastSeenAt: DateTime.parse(json['lastSeenAt']! as String).toUtc(),
    revokedAt: json['revokedAt'] == null
        ? null
        : DateTime.parse(json['revokedAt']! as String).toUtc(),
  );
}

class SyncSpaceState {
  const SyncSpaceState({
    required this.id,
    required this.keyEpoch,
    required this.groupKey,
  });

  final String id;
  final int keyEpoch;
  final List<int> groupKey;
}

class DeviceIdentity {
  const DeviceIdentity({required this.device, required this.privateKey});

  final TrustedDevice device;
  final List<int> privateKey;
}
