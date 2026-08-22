import 'package:leeef_reader/src/sync/versioned_entity.dart';

/// Deterministic last-write-wins resolution used for one stable entity ID.
///
/// Wall-clock time is the primary ordering key. An operation ID is the stable
/// tie-breaker, so all devices reach the same result even when timestamps are
/// equal. Tombstones participate in the same ordering and therefore cannot be
/// accidentally resurrected by an older upsert.
VersionedEntity<T> resolveConflict<T>(
  VersionedEntity<T> local,
  VersionedEntity<T> remote,
) {
  if (local.id != remote.id) {
    throw ArgumentError('Only entities with the same stable ID can conflict.');
  }

  final timestampOrder = local.modifiedAt.compareTo(remote.modifiedAt);
  if (timestampOrder > 0) return local;
  if (timestampOrder < 0) return remote;

  final operationOrder = local.operationId.compareTo(remote.operationId);
  if (operationOrder > 0) return local;
  if (operationOrder < 0) return remote;

  // This should only happen when the same operation was downloaded twice.
  // Prefer a tombstone to avoid resurrecting data from a malformed duplicate.
  if (local.isDeleted != remote.isDeleted) {
    return local.isDeleted ? local : remote;
  }
  return local;
}

Map<String, VersionedEntity<T>> mergeEntitySets<T>(
  Iterable<VersionedEntity<T>> local,
  Iterable<VersionedEntity<T>> remote,
) {
  final merged = <String, VersionedEntity<T>>{};
  for (final entity in [...local, ...remote]) {
    final current = merged[entity.id];
    merged[entity.id] = current == null
        ? entity
        : resolveConflict(current, entity);
  }
  return merged;
}
