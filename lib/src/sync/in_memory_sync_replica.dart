import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/conflict_resolver.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';
import 'package:leeef_reader/src/sync/versioned_entity.dart';

/// Executable reference model for the operation-log sync protocol.
///
/// Production backends persist the same state in Drift and object storage. The
/// small in-memory model makes convergence and idempotency rules testable
/// without network or SQLite timing affecting the result.
class InMemorySyncReplica {
  final Set<String> _appliedOperationIds = {};
  final Map<String, SyncOperation> _operations = {};
  final Map<String, VersionedEntity<Map<String, Object?>>> _entities = {};

  Iterable<SyncOperation> get operations => _operations.values;

  bool hasApplied(String operationId) =>
      _appliedOperationIds.contains(operationId);

  bool apply(SyncOperation operation) {
    if (!_appliedOperationIds.add(operation.operationId)) return false;

    final candidate = VersionedEntity<Map<String, Object?>>(
      id: operation.entityKey,
      value: Map.unmodifiable(operation.payload),
      modifiedAt: operation.occurredAt.toUtc(),
      deviceId: operation.deviceId,
      operationId: operation.operationId,
      isDeleted: operation.kind == OperationKind.delete,
    );
    final current = _entities[operation.entityKey];
    _entities[operation.entityKey] = current == null
        ? candidate
        : resolveConflict(current, candidate);
    _operations[operation.operationId] = operation;
    return true;
  }

  void applyAll(Iterable<SyncOperation> operations) {
    for (final operation in operations) {
      apply(operation);
    }
  }

  Map<String, Object?>? visibleEntity(EntityType type, String id) {
    final entity = _entities['${type.name}:$id'];
    if (entity == null || entity.isDeleted) return null;
    return entity.value;
  }

  bool isDeleted(EntityType type, String id) =>
      _entities['${type.name}:$id']?.isDeleted ?? false;
}
