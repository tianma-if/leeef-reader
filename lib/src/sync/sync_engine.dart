import 'dart:io';

import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_sync_service.dart';

class SyncReport {
  const SyncReport({
    required this.uploadedOperations,
    required this.downloadedOperations,
    required this.downloadedBooks,
    required this.downloadedCovers,
    this.trustedSync,
  });

  final int uploadedOperations;
  final int downloadedOperations;
  final int downloadedBooks;
  final int downloadedCovers;
  final TrustedSyncReport? trustedSync;
}

class SyncEngine {
  SyncEngine({
    required LibraryRepository repository,
    required SyncBackend backend,
    required Directory libraryDirectory,
    TrustedSyncService? trustedSyncService,
  }) : _repository = repository,
       _backend = backend,
       _libraryDirectory = libraryDirectory,
       _trustedSyncService = trustedSyncService;

  final LibraryRepository _repository;
  final SyncBackend _backend;
  final Directory _libraryDirectory;
  final TrustedSyncService? _trustedSyncService;

  Future<SyncReport> synchronize() async {
    var uploaded = 0;
    for (final operation in await _repository.pendingSyncOperations()) {
      if (operation.entityType == EntityType.book &&
          operation.kind == OperationKind.upsert) {
        final book = await _repository.getBook(operation.entityId);
        final path = book?.filePath;
        if (book != null && path != null && book.isAvailableLocally) {
          await _backend.uploadBlob(book.sha256, File(path));
        }
        final coverPath = book?.coverPath;
        final coverHash = book?.coverSha256;
        if (coverPath != null && coverHash != null) {
          await _backend.uploadBlob(coverHash, File(coverPath));
        }
      }
      await _backend.appendOperation(operation);
      await _repository.markOperationSynchronized(operation.operationId);
      uploaded++;
    }

    var downloaded = 0;
    for (final operation in await _backend.listOperations()) {
      if (await _repository.applyRemoteOperation(operation)) downloaded++;
    }

    await _libraryDirectory.create(recursive: true);
    var downloadedBooks = 0;
    var downloadedCovers = 0;
    for (final book in await _repository.listBooks()) {
      if (await downloadBook(book.id)) downloadedBooks++;
      if (await _downloadCover(book.id)) downloadedCovers++;
    }

    TrustedSyncReport? trustedSync;
    if (_trustedSyncService case final service?
        when _backend is SyncDocumentBackend) {
      trustedSync = await service.synchronize(_backend as SyncDocumentBackend);
    }

    return SyncReport(
      uploadedOperations: uploaded,
      downloadedOperations: downloaded,
      downloadedBooks: downloadedBooks,
      downloadedCovers: downloadedCovers,
      trustedSync: trustedSync,
    );
  }

  Future<bool> downloadBook(String bookId) async {
    final book = await _repository.getBook(bookId);
    if (book == null || book.isDeleted) {
      throw StateError('Book $bookId does not exist.');
    }
    final path = book.filePath;
    if (book.isAvailableLocally && path != null && await File(path).exists()) {
      return false;
    }
    if (!await _backend.hasBlob(book.sha256)) return false;
    await _libraryDirectory.create(recursive: true);
    final extension = switch (book.mediaType) {
      'application/epub+zip' => 'epub',
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      'application/x-mobipocket-ebook' => 'mobi',
      'application/vnd.amazon.ebook' => 'azw3',
      'application/x-fictionbook+xml' => 'fb2',
      _ => 'bin',
    };
    final destination = File(
      '${_libraryDirectory.path}/${book.sha256}.$extension',
    );
    await _backend.downloadBlob(book.sha256, destination);
    await _repository.attachLocalBookFile(
      bookId: book.id,
      filePath: destination.path,
    );
    return true;
  }

  Future<bool> _downloadCover(String bookId) async {
    final book = await _repository.getBook(bookId);
    final coverHash = book?.coverSha256;
    if (book == null || coverHash == null) return false;
    final currentPath = book.coverPath;
    if (currentPath != null && await File(currentPath).exists()) return false;
    if (!await _backend.hasBlob(coverHash)) return false;
    await _libraryDirectory.create(recursive: true);
    final destination = File('${_libraryDirectory.path}/$coverHash.cover');
    await _backend.downloadBlob(coverHash, destination);
    await _repository.attachLocalCoverFile(
      bookId: book.id,
      coverPath: destination.path,
    );
    return true;
  }
}
