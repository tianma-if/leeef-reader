class VersionedEntity<T> {
  const VersionedEntity({
    required this.id,
    required this.value,
    required this.modifiedAt,
    required this.deviceId,
    required this.operationId,
    this.isDeleted = false,
  });

  final String id;
  final T value;
  final DateTime modifiedAt;
  final String deviceId;
  final String operationId;
  final bool isDeleted;
}
