import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/entity_type.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';
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

  Future<List<BookRecord>> listBooks() {
    return (_database.select(
      _database.books,
    )..where((book) => book.isDeleted.equals(false))).get();
  }

  Future<ReadingProgressRecord?> getReadingProgress(String bookId) {
    return (_database.select(
      _database.readingProgresses,
    )..where((progress) => progress.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<List<SyncOperation>> pendingSyncOperations() async {
    final query = _database.select(_database.syncOperations)
      ..where((operation) => operation.appliedAt.isNull())
      ..orderBy([
        (operation) => OrderingTerm.asc(operation.occurredAt),
        (operation) => OrderingTerm.asc(operation.operationId),
      ]);
    return (await query.get())
        .map(_operationFromRecord)
        .toList(growable: false);
  }

  Future<void> markOperationSynchronized(String operationId) async {
    final affected =
        await (_database.update(_database.syncOperations)
              ..where((operation) => operation.operationId.equals(operationId)))
            .write(
              SyncOperationsCompanion(appliedAt: Value(DateTime.now().toUtc())),
            );
    if (affected != 1) {
      throw StateError('Sync operation $operationId does not exist.');
    }
  }

  /// Applies one downloaded operation exactly once using deterministic LWW.
  Future<bool> applyRemoteOperation(SyncOperation operation) async {
    return _database.transaction(() async {
      final duplicate =
          await (_database.select(_database.syncOperations)
                ..where((row) => row.operationId.equals(operation.operationId)))
              .getSingleOrNull();
      if (duplicate != null) return false;

      final latest =
          await (_database.select(_database.syncOperations)
                ..where(
                  (row) =>
                      row.entityType.equals(operation.entityType.name) &
                      row.entityId.equals(operation.entityId),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.occurredAt),
                  (row) => OrderingTerm.desc(row.operationId),
                ])
                ..limit(1))
              .getSingleOrNull();
      final wins =
          latest == null ||
          latest.occurredAt.isBefore(operation.occurredAt) ||
          (latest.occurredAt.isAtSameMomentAs(operation.occurredAt) &&
              latest.operationId.compareTo(operation.operationId) < 0);
      if (wins) await _applyEntityOperation(operation);

      await _database
          .into(_database.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              operationId: operation.operationId,
              deviceId: operation.deviceId,
              entityType: operation.entityType.name,
              entityId: operation.entityId,
              kind: operation.kind.name,
              payloadJson: Value(jsonEncode(operation.payload)),
              occurredAt: operation.occurredAt.toUtc(),
              appliedAt: Value(DateTime.now().toUtc()),
            ),
          );
      return true;
    });
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

  Future<void> updateBookMetadata({
    required String bookId,
    required String title,
    String? author,
    String? description,
  }) async {
    final current = await getBook(bookId);
    if (current == null) throw StateError('Book $bookId does not exist.');
    if (current.title == title &&
        current.author == author &&
        current.description == description) {
      return;
    }
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'sha256': current.sha256,
      'title': title,
      'author': author,
      'description': description,
      'mediaType': current.mediaType,
      'coverPath': current.coverPath,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.books,
      )..where((book) => book.id.equals(bookId))).write(
        BooksCompanion(
          title: Value(title),
          author: Value(author),
          description: Value(description),
          updatedAt: Value(now),
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

  Future<void> attachLocalBookFile({
    required String bookId,
    required String filePath,
  }) async {
    final affected =
        await (_database.update(
          _database.books,
        )..where((book) => book.id.equals(bookId))).write(
          BooksCompanion(
            filePath: Value(filePath),
            isAvailableLocally: const Value(true),
          ),
        );
    if (affected != 1) throw StateError('Book $bookId does not exist.');
  }

  Future<void> _applyEntityOperation(SyncOperation operation) async {
    final deleted = operation.kind == OperationKind.delete;
    final payload = operation.payload;
    switch (operation.entityType) {
      case EntityType.book:
        final existing = await getBook(operation.entityId);
        if (deleted) {
          if (existing != null) {
            await (_database.update(
              _database.books,
            )..where((book) => book.id.equals(operation.entityId))).write(
              BooksCompanion(
                isDeleted: const Value(true),
                updatedAt: Value(operation.occurredAt.toUtc()),
              ),
            );
          }
          return;
        }
        if (existing == null) {
          await _database
              .into(_database.books)
              .insert(
                BooksCompanion.insert(
                  id: operation.entityId,
                  sha256: payload['sha256']! as String,
                  title: payload['title']! as String,
                  author: Value(payload['author'] as String?),
                  description: Value(payload['description'] as String?),
                  mediaType: payload['mediaType']! as String,
                  coverPath: Value(payload['coverPath'] as String?),
                  isAvailableLocally: const Value(false),
                  createdAt: operation.occurredAt.toUtc(),
                  updatedAt: operation.occurredAt.toUtc(),
                ),
              );
        } else {
          await (_database.update(
            _database.books,
          )..where((book) => book.id.equals(operation.entityId))).write(
            BooksCompanion(
              title: Value(payload['title']! as String),
              author: Value(payload['author'] as String?),
              description: Value(payload['description'] as String?),
              coverPath: Value(payload['coverPath'] as String?),
              isDeleted: const Value(false),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
        }
        return;
      case EntityType.excerpt:
        if (deleted) {
          await (_database.update(
            _database.excerpts,
          )..where((excerpt) => excerpt.id.equals(operation.entityId))).write(
            ExcerptsCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          return;
        }
        await _database
            .into(_database.excerpts)
            .insertOnConflictUpdate(
              ExcerptsCompanion.insert(
                id: operation.entityId,
                bookId: payload['bookId']! as String,
                locator: payload['locator']! as String,
                quote: payload['quote']! as String,
                note: Value(payload['note'] as String?),
                color: Value(payload['color'] as String? ?? 'yellow'),
                createdAt: operation.occurredAt.toUtc(),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.bookmark:
        if (deleted) {
          await (_database.update(
            _database.bookmarks,
          )..where((bookmark) => bookmark.id.equals(operation.entityId))).write(
            BookmarksCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          return;
        }
        await _database
            .into(_database.bookmarks)
            .insertOnConflictUpdate(
              BookmarksCompanion.insert(
                id: operation.entityId,
                bookId: payload['bookId']! as String,
                locator: payload['locator']! as String,
                title: Value(payload['title'] as String?),
                note: Value(payload['note'] as String?),
                createdAt: operation.occurredAt.toUtc(),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.readingProgress:
        if (deleted) return;
        final location = ReadingLocation.fromJson(payload);
        await _database
            .into(_database.readingProgresses)
            .insertOnConflictUpdate(
              ReadingProgressesCompanion.insert(
                bookId: operation.entityId,
                locator: location.locator,
                progress: location.progress,
                chapterTitle: Value(location.chapterTitle),
                page: Value(location.page),
                deviceId: operation.deviceId,
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.bookshelf:
        // Bookshelf UI is outside the first vertical slice, but downloaded
        // operations are retained so a later schema adapter can replay them.
        return;
    }
  }

  static SyncOperation _operationFromRecord(SyncOperationRecord record) {
    final decoded = record.payloadJson == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(record.payloadJson!) as Map);
    return SyncOperation(
      operationId: record.operationId,
      deviceId: record.deviceId,
      entityType: EntityType.values.byName(record.entityType),
      entityId: record.entityId,
      kind: OperationKind.values.byName(record.kind),
      occurredAt: record.occurredAt.toUtc(),
      payload: decoded,
    );
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
