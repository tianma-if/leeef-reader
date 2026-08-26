import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';

class LibraryStorageReport {
  const LibraryStorageReport({
    required this.bookBytes,
    required this.coverBytes,
    required this.orphanBytes,
    required this.localBooks,
    required this.missingBooks,
    required this.md5Missing,
  });
  final int bookBytes;
  final int coverBytes;
  final int orphanBytes;
  final int localBooks;
  final List<BookRecord> missingBooks;
  final int md5Missing;
  int get totalBytes => bookBytes + coverBytes + orphanBytes;
}

class LibraryMaintenanceService {
  const LibraryMaintenanceService({
    required LibraryRepository repository,
    required Directory libraryDirectory,
  }) : _repository = repository,
       _libraryDirectory = libraryDirectory;

  final LibraryRepository _repository;
  final Directory _libraryDirectory;

  Future<LibraryStorageReport> inspect() async {
    final books = await _repository.listBooks();
    final referenced = <String>{};
    final missing = <BookRecord>[];
    var bookBytes = 0;
    var coverBytes = 0;
    var localBooks = 0;
    for (final book in books) {
      final path = book.filePath;
      if (path != null && book.isAvailableLocally) {
        final file = File(path);
        if (await file.exists()) {
          localBooks++;
          referenced.add(file.absolute.path);
          bookBytes += await file.length();
        } else {
          missing.add(book);
        }
      }
      final coverPath = book.coverPath;
      if (coverPath != null) {
        final cover = File(coverPath);
        if (await cover.exists()) {
          referenced.add(cover.absolute.path);
          coverBytes += await cover.length();
        }
      }
    }
    var orphanBytes = 0;
    if (await _libraryDirectory.exists()) {
      await for (final entity in _libraryDirectory.list(recursive: true)) {
        if (entity is File &&
            !_isDatabaseFile(entity) &&
            !referenced.contains(entity.absolute.path)) {
          orphanBytes += await entity.length();
        }
      }
    }
    return LibraryStorageReport(
      bookBytes: bookBytes,
      coverBytes: coverBytes,
      orphanBytes: orphanBytes,
      localBooks: localBooks,
      missingBooks: missing,
      md5Missing: books.where((book) => book.md5 == null).length,
    );
  }

  Future<int> backfillMd5() async {
    var updated = 0;
    for (final book in await _repository.listBooks()) {
      if (book.md5 != null || book.filePath == null) continue;
      final file = File(book.filePath!);
      if (!await file.exists()) continue;
      final digest = (await md5.bind(file.openRead()).first).toString();
      await _repository.updateBookMd5(bookId: book.id, md5: digest);
      updated++;
    }
    return updated;
  }

  Future<int> repairMissingFileFlags() async {
    var repaired = 0;
    for (final book in await _repository.listBooks()) {
      if (!book.isAvailableLocally || book.filePath == null) continue;
      if (!await File(book.filePath!).exists()) {
        await _repository.detachLocalBookFile(book.id);
        repaired++;
      }
    }
    return repaired;
  }

  Future<int> clearOrphanFiles() async {
    final books = await _repository.listBooks();
    final referenced = <String>{
      for (final book in books)
        ...[
          book.filePath,
          book.coverPath,
        ].whereType<String>().map((path) => File(path).absolute.path),
    };
    var deletedBytes = 0;
    if (!await _libraryDirectory.exists()) return 0;
    await for (final entity in _libraryDirectory.list(recursive: true)) {
      if (entity is! File ||
          _isDatabaseFile(entity) ||
          referenced.contains(entity.absolute.path)) {
        continue;
      }
      deletedBytes += await entity.length();
      await entity.delete();
    }
    return deletedBytes;
  }

  /// Copies every referenced book and cover first, updates database pointers,
  /// then removes the old files. Any failure restores the old pointers and
  /// deletes newly created copies.
  Future<int> migrateFilesTo(Directory destination) async {
    await destination.create(recursive: true);
    final books = await _repository.listBooks();
    final copied = <File>[];
    final updates =
        <({BookRecord book, String? bookPath, String? coverPath})>[];
    var migrated = 0;
    try {
      for (final book in books) {
        String? nextBookPath;
        String? nextCoverPath;
        final sourcePath = book.filePath;
        if (sourcePath != null && await File(sourcePath).exists()) {
          final extension = sourcePath.contains('.')
              ? sourcePath.substring(sourcePath.lastIndexOf('.'))
              : '.book';
          final target = File('${destination.path}/${book.sha256}$extension');
          if (target.absolute.path != File(sourcePath).absolute.path) {
            if (await _atomicCopy(File(sourcePath), target)) copied.add(target);
            nextBookPath = target.path;
          }
        }
        final sourceCover = book.coverPath;
        if (sourceCover != null && await File(sourceCover).exists()) {
          final hash = book.coverSha256 ?? '${book.id}-cover';
          final target = File('${destination.path}/$hash.cover');
          if (target.absolute.path != File(sourceCover).absolute.path) {
            if (await _atomicCopy(File(sourceCover), target)) {
              copied.add(target);
            }
            nextCoverPath = target.path;
          }
        }
        if (nextBookPath != null || nextCoverPath != null) {
          updates.add((
            book: book,
            bookPath: nextBookPath,
            coverPath: nextCoverPath,
          ));
        }
      }
      for (final update in updates) {
        if (update.bookPath != null) {
          await _repository.attachLocalBookFile(
            bookId: update.book.id,
            filePath: update.bookPath!,
          );
          migrated++;
        }
        if (update.coverPath != null) {
          await _repository.attachLocalCoverFile(
            bookId: update.book.id,
            coverPath: update.coverPath!,
          );
        }
      }
    } on Object {
      for (final update in updates) {
        if (update.bookPath != null && update.book.filePath != null) {
          await _repository.attachLocalBookFile(
            bookId: update.book.id,
            filePath: update.book.filePath!,
          );
        }
        if (update.coverPath != null && update.book.coverPath != null) {
          await _repository.attachLocalCoverFile(
            bookId: update.book.id,
            coverPath: update.book.coverPath!,
          );
        }
      }
      for (final file in copied.reversed) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
    for (final update in updates) {
      for (final oldPath in [update.book.filePath, update.book.coverPath]) {
        if (oldPath == null) continue;
        final old = File(oldPath);
        if (copied.every((file) => file.absolute.path != old.absolute.path) &&
            await old.exists()) {
          await old.delete();
        }
      }
    }
    return migrated;
  }

  static Future<bool> _atomicCopy(File source, File target) async {
    await target.parent.create(recursive: true);
    if (await target.exists()) return false;
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();
    await source.copy(partial.path);
    await partial.rename(target.path);
    return true;
  }

  static bool _isDatabaseFile(File file) {
    final name = file.uri.pathSegments.last;
    return name == 'leeef.sqlite' ||
        name == 'leeef.sqlite-wal' ||
        name == 'leeef.sqlite-shm';
  }
}
