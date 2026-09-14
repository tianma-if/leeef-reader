import 'package:leeef_reader/src/domain/entity_type.dart';

class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.occurredAt,
    required this.payload,
  });

  final String operationId;
  final String deviceId;
  final EntityType entityType;
  final String entityId;
  final OperationKind kind;
  final DateTime occurredAt;
  final Map<String, Object?> payload;

  String get entityKey => '${entityType.name}:$entityId';

  SyncOperation copyWith({String? entityId, Map<String, Object?>? payload}) =>
      SyncOperation(
        operationId: operationId,
        deviceId: deviceId,
        entityType: entityType,
        entityId: entityId ?? this.entityId,
        kind: kind,
        occurredAt: occurredAt,
        payload: payload ?? this.payload,
      );

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'deviceId': deviceId,
    'entityType': entityType.name,
    'entityId': entityId,
    'kind': kind.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'payload': payload,
  };

  factory SyncOperation.fromJson(Map<String, Object?> json) {
    return SyncOperation(
      operationId: json['operationId']! as String,
      deviceId: json['deviceId']! as String,
      entityType: EntityType.values.byName(json['entityType']! as String),
      entityId: json['entityId']! as String,
      kind: OperationKind.values.byName(json['kind']! as String),
      occurredAt: DateTime.parse(json['occurredAt']! as String).toUtc(),
      payload: Map<String, Object?>.from(json['payload']! as Map),
    );
  }
}
