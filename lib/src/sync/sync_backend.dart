import 'dart:io';

import 'package:leeef_reader/src/sync/sync_operation.dart';

abstract interface class SyncBackend {
  Future<void> uploadBlob(String sha256, File source);

  Future<bool> hasBlob(String sha256);

  Future<void> downloadBlob(String sha256, File destination);

  Future<void> appendOperation(SyncOperation operation);

  Future<List<SyncOperation>> listOperations();
}

/// Optional small-object storage used by encrypted configuration and trusted
/// device metadata. Paths are relative to the configured Leeef sync root.
abstract interface class SyncDocumentBackend {
  Future<void> writeDocument(String path, List<int> bytes);

  /// Writes a document only when the path does not exist.
  Future<bool> writeDocumentIfAbsent(String path, List<int> bytes);

  Future<List<int>?> readDocument(String path);

  Future<List<String>> listDocuments(String prefix);

  Future<void> deleteDocument(String path);
}

class SyncUnavailable implements Exception {
  const SyncUnavailable(this.message);

  final String message;

  @override
  String toString() => 'Sync unavailable: $message';
}

class SyncIntegrityException implements Exception {
  const SyncIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'Sync integrity failure: $message';
}
