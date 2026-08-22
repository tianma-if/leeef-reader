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
}
