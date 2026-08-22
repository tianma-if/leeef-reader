import 'dart:io';

import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';

class SyncReport {
  const SyncReport({
    required this.uploadedOperations,
    required this.downloadedOperations,
    required this.downloadedBooks,
  });

  final int uploadedOperations;
  final int downloadedOperations;
  final int downloadedBooks;
}

class SyncEngine {
  SyncEngine({
    required LibraryRepository repository,
    required SyncBackend backend,
    required Directory libraryDirectory,
  }) : _repository = repository,
       _backend = backend,
       _libraryDirectory = libraryDirectory;

  final LibraryRepository _repository;
  final SyncBackend _backend;
  final Directory _libraryDirectory;

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
    for (final book in await _repository.listBooks()) {
      if (book.isAvailableLocally || !await _backend.hasBlob(book.sha256)) {
        continue;
      }
      final extension = book.mediaType == 'application/epub+zip'
          ? 'epub'
          : 'bin';
      final destination = File(
        '${_libraryDirectory.path}/${book.sha256}.$extension',
      );
      await _backend.downloadBlob(book.sha256, destination);
      await _repository.attachLocalBookFile(
        bookId: book.id,
        filePath: destination.path,
      );
      downloadedBooks++;
    }

    return SyncReport(
      uploadedOperations: uploaded,
      downloadedOperations: downloaded,
      downloadedBooks: downloadedBooks,
    );
  }
}
