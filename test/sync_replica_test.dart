import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/in_memory_sync_replica.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

void main() {
  SyncOperation operation({
    required String operationId,
    required String deviceId,
    required String entityId,
    required DateTime occurredAt,
    required Map<String, Object?> payload,
    OperationKind kind = OperationKind.upsert,
  }) {
    return SyncOperation(
      operationId: operationId,
      deviceId: deviceId,
      entityType: EntityType.excerpt,
      entityId: entityId,
      kind: kind,
      occurredAt: occurredAt,
      payload: payload,
    );
  }

  test('two devices converge after out-of-order exchange', () {
    final deviceA = InMemorySyncReplica();
    final deviceB = InMemorySyncReplica();
    final initial = operation(
      operationId: '01-initial',
      deviceId: 'device-a',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026, 1, 1, 10),
      payload: const {'quote': 'original', 'note': null},
    );
    final editA = operation(
      operationId: '02-edit-a',
      deviceId: 'device-a',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026, 1, 1, 11),
      payload: const {'quote': 'original', 'note': 'older note'},
    );
    final editB = operation(
      operationId: '03-edit-b',
      deviceId: 'device-b',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026, 1, 1, 12),
      payload: const {'quote': 'original', 'note': 'newer note'},
    );

    deviceA.applyAll([initial, editA, editB]);
    deviceB.applyAll([editB, initial, editA]);

    expect(
      deviceA.visibleEntity(EntityType.excerpt, 'excerpt-1'),
      deviceB.visibleEntity(EntityType.excerpt, 'excerpt-1'),
    );
    expect(
      deviceA.visibleEntity(EntityType.excerpt, 'excerpt-1')?['note'],
      'newer note',
    );
  });

  test('replayed operation is idempotent', () {
    final replica = InMemorySyncReplica();
    final create = operation(
      operationId: '01-create',
      deviceId: 'device-a',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026),
      payload: const {'quote': 'once'},
    );

    expect(replica.apply(create), isTrue);
    expect(replica.apply(create), isFalse);
    expect(replica.operations, hasLength(1));
  });

  test('newer tombstone survives stale upsert arriving later', () {
    final replica = InMemorySyncReplica();
    final staleUpsert = operation(
      operationId: '01-create',
      deviceId: 'device-a',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026, 1, 1),
      payload: const {'quote': 'deleted quote'},
    );
    final deletion = operation(
      operationId: '02-delete',
      deviceId: 'device-b',
      entityId: 'excerpt-1',
      occurredAt: DateTime.utc(2026, 1, 2),
      payload: const {},
      kind: OperationKind.delete,
    );

    replica.applyAll([deletion, staleUpsert]);

    expect(replica.visibleEntity(EntityType.excerpt, 'excerpt-1'), isNull);
    expect(replica.isDeleted(EntityType.excerpt, 'excerpt-1'), isTrue);
  });

  test('concurrent entities with different stable IDs are both retained', () {
    final replica = InMemorySyncReplica();
    replica.applyAll([
      operation(
        operationId: '01-a',
        deviceId: 'device-a',
        entityId: 'excerpt-a',
        occurredAt: DateTime.utc(2026),
        payload: const {'quote': 'A'},
      ),
      operation(
        operationId: '01-b',
        deviceId: 'device-b',
        entityId: 'excerpt-b',
        occurredAt: DateTime.utc(2026),
        payload: const {'quote': 'B'},
      ),
    ]);

    expect(replica.visibleEntity(EntityType.excerpt, 'excerpt-a'), isNotNull);
    expect(replica.visibleEntity(EntityType.excerpt, 'excerpt-b'), isNotNull);
  });
}
