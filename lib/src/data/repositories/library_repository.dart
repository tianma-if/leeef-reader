import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:uuid/uuid.dart';

/// The only local write path for core library data.
///
/// Every mutation and its sync operation are committed in one transaction. A
/// caller must never write a core table directly, otherwise another device
/// cannot observe that change.
class LibraryRepository {
  LibraryRepository({
    required AppDatabase database,
    required String deviceId,
    String Function()? idGenerator,
  }) : _database = database,
       _deviceId = deviceId,
       _idGenerator = idGenerator ?? const Uuid().v7;

  final AppDatabase _database;
  final String _deviceId;
  final String Function() _idGenerator;

  Stream<List<BookRecord>> watchLibrary() {
    final query = _database.select(_database.books)
      ..where((book) => book.isDeleted.equals(false))
      ..orderBy([(book) => OrderingTerm.desc(book.updatedAt)]);
    return query.watch();
  }

  Stream<List<ExcerptRecord>> watchExcerpts({String? bookId}) {
    final query = _database.select(_database.excerpts)
      ..where((excerpt) {
        final visible = excerpt.isDeleted.equals(false);
        return bookId == null
            ? visible
            : visible & excerpt.bookId.equals(bookId);
      })
      ..orderBy([(excerpt) => OrderingTerm.desc(excerpt.updatedAt)]);
    return query.watch();
  }

  Future<BookRecord?> getBook(String bookId) {
    return (_database.select(
      _database.books,
    )..where((book) => book.id.equals(bookId))).getSingleOrNull();
  }

  Future<ReadingProgressRecord?> getReadingProgress(String bookId) {
    return (_database.select(
      _database.readingProgresses,
    )..where((progress) => progress.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<String> createBookMetadata({
    required String sha256,
    required String title,
    required String mediaType,
    String? author,
    String? description,
    String? filePath,
    String? coverPath,
  }) async {
    final normalizedHash = sha256.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizedHash)) {
      throw ArgumentError.value(sha256, 'sha256', 'Expected 64 hex digits.');
    }

    final duplicate = await (_database.select(
      _database.books,
    )..where((book) => book.sha256.equals(normalizedHash))).getSingleOrNull();
    if (duplicate != null) {
      if (filePath != null &&
          (duplicate.filePath != filePath || !duplicate.isAvailableLocally)) {
        await (_database.update(
          _database.books,
        )..where((book) => book.id.equals(duplicate.id))).write(
          BooksCompanion(
            filePath: Value(filePath),
            isAvailableLocally: const Value(true),
          ),
        );
      }
      return duplicate.id;
    }

    final bookId = _idGenerator();
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': bookId,
      'sha256': normalizedHash,
      'title': title,
      'author': author,
      'description': description,
      'mediaType': mediaType,
      'coverPath': coverPath,
    };

    await _database.transaction(() async {
      await _database
          .into(_database.books)
          .insert(
            BooksCompanion.insert(
              id: bookId,
              sha256: normalizedHash,
              title: title,
              author: Value(author),
              description: Value(description),
              mediaType: mediaType,
              filePath: Value(filePath),
              coverPath: Value(coverPath),
              isAvailableLocally: Value(filePath != null),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.book,
        entityId: bookId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
    return bookId;
  }

  Future<void> updateReadingProgress({
    required String bookId,
    required ReadingLocation location,
  }) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();

    await _database.transaction(() async {
      await _database
          .into(_database.readingProgresses)
          .insertOnConflictUpdate(
            ReadingProgressesCompanion.insert(
              bookId: bookId,
              locator: location.locator,
              progress: location.progress,
              chapterTitle: Value(location.chapterTitle),
              page: Value(location.page),
              deviceId: _deviceId,
              updatedAt: now,
            ),
          );
      await _database
          .into(_database.readingProgressHistory)
          .insert(
            ReadingProgressHistoryCompanion.insert(
              operationId: operationId,
              bookId: bookId,
              locator: location.locator,
              progress: location.progress,
              chapterTitle: Value(location.chapterTitle),
              page: Value(location.page),
              deviceId: _deviceId,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.readingProgress,
        entityId: bookId,
        kind: OperationKind.upsert,
        payload: location.toJson(),
        occurredAt: now,
      );
    });
  }

  Future<String> createExcerpt({
    required String bookId,
    required String locator,
    required String quote,
    String? note,
    String color = 'yellow',
  }) async {
    if (quote.trim().isEmpty) {
      throw ArgumentError.value(quote, 'quote', 'Excerpt quote is empty.');
    }
    final excerptId = _idGenerator();
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': excerptId,
      'bookId': bookId,
      'locator': locator,
      'quote': quote,
      'note': note,
      'color': color,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.excerpts)
          .insert(
            ExcerptsCompanion.insert(
              id: excerptId,
              bookId: bookId,
              locator: locator,
              quote: quote,
              note: Value(note),
              color: Value(color),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.excerpt,
        entityId: excerptId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
    return excerptId;
  }

  Future<String> createBookmark({
    required String bookId,
    required String locator,
    String? title,
    String? note,
  }) async {
    final bookmarkId = _idGenerator();
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': bookmarkId,
      'bookId': bookId,
      'locator': locator,
      'title': title,
      'note': note,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              id: bookmarkId,
              bookId: bookId,
              locator: locator,
              title: Value(title),
              note: Value(note),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookmark,
        entityId: bookmarkId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
    return bookmarkId;
  }

  Future<void> softDeleteBook(String bookId) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      final affected =
          await (_database.update(
            _database.books,
          )..where((book) => book.id.equals(bookId))).write(
            BooksCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
          );
      if (affected != 1) throw StateError('Book $bookId does not exist.');

      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.book,
        entityId: bookId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
  }

  Future<void> _appendOperation({
    required String operationId,
    required EntityType entityType,
    required String entityId,
    required OperationKind kind,
    required Map<String, Object?> payload,
    required DateTime occurredAt,
  }) {
    return _database
        .into(_database.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            operationId: operationId,
            deviceId: _deviceId,
            entityType: entityType.name,
            entityId: entityId,
            kind: kind.name,
            payloadJson: Value(jsonEncode(payload)),
            occurredAt: occurredAt,
          ),
        );
  }
}
