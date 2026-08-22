import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/sync/conflict_resolver.dart';
import 'package:leeef_reader/src/sync/versioned_entity.dart';

void main() {
  VersionedEntity<String> entity({
    required String value,
    required DateTime modifiedAt,
    required String operationId,
    bool isDeleted = false,
  }) {
    return VersionedEntity(
      id: 'same-id',
      value: value,
      modifiedAt: modifiedAt,
      deviceId: value,
      operationId: operationId,
      isDeleted: isDeleted,
    );
  }

  test('newer entity wins regardless of input order', () {
    final older = entity(
      value: 'device-a',
      modifiedAt: DateTime.utc(2026, 1, 1),
      operationId: '01-old',
    );
    final newer = entity(
      value: 'device-b',
      modifiedAt: DateTime.utc(2026, 1, 2),
      operationId: '02-new',
    );

    expect(resolveConflict(older, newer), same(newer));
    expect(resolveConflict(newer, older), same(newer));
  });

  test('operation ID deterministically breaks equal timestamp ties', () {
    final low = entity(
      value: 'device-a',
      modifiedAt: DateTime.utc(2026),
      operationId: '01-a',
    );
    final high = entity(
      value: 'device-b',
      modifiedAt: DateTime.utc(2026),
      operationId: '01-b',
    );

    expect(resolveConflict(low, high), same(high));
    expect(resolveConflict(high, low), same(high));
  });

  test('older upsert cannot resurrect a newer tombstone', () {
    final upsert = entity(
      value: 'present',
      modifiedAt: DateTime.utc(2026, 1, 1),
      operationId: '01-upsert',
    );
    final tombstone = entity(
      value: 'deleted',
      modifiedAt: DateTime.utc(2026, 1, 2),
      operationId: '02-delete',
      isDeleted: true,
    );

    expect(resolveConflict(upsert, tombstone), same(tombstone));
  });

  test('stable IDs merge independently', () {
    final merged = mergeEntitySets(
      [
        VersionedEntity(
          id: 'excerpt-a',
          value: 'A',
          modifiedAt: DateTime.utc(2026),
          deviceId: 'one',
          operationId: '01',
        ),
      ],
      [
        VersionedEntity(
          id: 'excerpt-b',
          value: 'B',
          modifiedAt: DateTime.utc(2026),
          deviceId: 'two',
          operationId: '02',
        ),
      ],
    );

    expect(merged.keys, containsAll(['excerpt-a', 'excerpt-b']));
  });
}
