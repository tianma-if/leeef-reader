import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

/// A durable backend for tests, local-network shares and manual backup.
///
/// It uses the same immutable blob/operation layout as the future S3 adapter,
/// making the full sync protocol executable without cloud credentials.
class DirectorySyncBackend implements SyncBackend {
  DirectorySyncBackend(this.root);

  final Directory root;

  @override
  Future<void> uploadBlob(String sha256, File source) async {
    _validateSegment(sha256, 'sha256');
    await _verifyDigest(source, sha256);
    final destination = File('${root.path}/blobs/$sha256/original');
    if (await destination.exists()) {
      await _verifyDigest(destination, sha256);
      return;
    }
    await destination.parent.create(recursive: true);
    await _copyAtomically(source, destination);
    try {
      await _verifyDigest(destination, sha256);
    } on Object {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<bool> hasBlob(String sha256) {
    _validateSegment(sha256, 'sha256');
    return File('${root.path}/blobs/$sha256/original').exists();
  }

  @override
  Future<void> downloadBlob(String sha256, File destination) async {
    _validateSegment(sha256, 'sha256');
    final source = File('${root.path}/blobs/$sha256/original');
    if (!await source.exists()) {
      throw SyncUnavailable('Blob $sha256 does not exist.');
    }
    if (await destination.exists()) {
      try {
        await _verifyDigest(destination, sha256);
        return;
      } on SyncIntegrityException {
        await destination.delete();
      }
    }
    await destination.parent.create(recursive: true);
    await _copyAtomically(source, destination);
    try {
      await _verifyDigest(destination, sha256);
    } on Object {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<void> appendOperation(SyncOperation operation) async {
    _validateSegment(operation.deviceId, 'deviceId');
    _validateSegment(operation.operationId, 'operationId');
    final destination = File(
      '${root.path}/ops/${operation.deviceId}/${operation.operationId}.json',
    );
    if (await destination.exists()) return;
    await destination.parent.create(recursive: true);
    final staging = File(
      '${destination.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    await staging.writeAsString(jsonEncode(operation.toJson()), flush: true);
    try {
      await staging.rename(destination.path);
    } on FileSystemException {
      if (!await destination.exists()) rethrow;
      if (await staging.exists()) await staging.delete();
    }
  }

  @override
  Future<List<SyncOperation>> listOperations() async {
    final directory = Directory('${root.path}/ops');
    if (!await directory.exists()) return const [];
    final files = await directory
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    final operations = <SyncOperation>[];
    for (final file in files) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Invalid sync operation document.');
      }
      operations.add(
        SyncOperation.fromJson(Map<String, Object?>.from(decoded)),
      );
    }
    operations.sort((left, right) {
      final time = left.occurredAt.compareTo(right.occurredAt);
      return time != 0 ? time : left.operationId.compareTo(right.operationId);
    });
    return operations;
  }

  static Future<void> _copyAtomically(File source, File destination) async {
    final staging = File(
      '${destination.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await source.openRead().pipe(staging.openWrite());
      await staging.rename(destination.path);
    } on Object {
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
  }

  static Future<void> _verifyDigest(File file, String expected) async {
    if (!await file.exists()) {
      throw SyncIntegrityException('Missing file ${file.path}.');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected.toLowerCase()) {
      throw SyncIntegrityException(
        'SHA-256 mismatch for ${file.path}: expected $expected, got $actual.',
      );
    }
  }

  static void _validateSegment(String value, String name) {
    if (value.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe storage key.');
    }
  }
}
