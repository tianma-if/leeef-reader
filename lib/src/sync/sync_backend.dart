import 'dart:io';

import 'package:leeef_reader/src/sync/sync_operation.dart';

abstract interface class SyncBackend {
  Future<void> uploadBlob(String sha256, File source);

  Future<bool> hasBlob(String sha256);

  Future<void> downloadBlob(String sha256, File destination);

  Future<void> appendOperation(SyncOperation operation);

  Future<List<SyncOperation>> listOperations();
}

class SyncUnavailable implements Exception {
  const SyncUnavailable(this.message);

  final String message;

  @override
  String toString() => 'Sync unavailable: $message';
}
