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

  Future<void> recordAuditEvent({
    required String caller,
    required String action,
    required Map<String, dynamic> parameters,
    required String result,
  }) => _database
      .into(_database.auditEvents)
      .insert(
        AuditEventsCompanion.insert(
          id: _idGenerator(),
          caller: caller,
          action: action,
          parametersJson: jsonEncode(parameters),
          result: result,
          occurredAt: DateTime.now().toUtc(),
        ),
      );

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

  Stream<List<BookmarkRecord>> watchBookmarks({String? bookId}) {
    final query = _database.select(_database.bookmarks)
      ..where((bookmark) {
        final visible = bookmark.isDeleted.equals(false);
        return bookId == null
            ? visible
            : visible & bookmark.bookId.equals(bookId);
      })
      ..orderBy([(bookmark) => OrderingTerm.desc(bookmark.updatedAt)]);
    return query.watch();
  }

  Stream<List<BookshelfRecord>> watchBookshelves() {
    final query = _database.select(_database.bookshelves)
      ..where((shelf) => shelf.isDeleted.equals(false))
      ..orderBy([
        (shelf) => OrderingTerm.asc(shelf.sortOrder),
        (shelf) => OrderingTerm.asc(shelf.name),
      ]);
    return query.watch();
  }

  Stream<List<TagRecord>> watchTags() {
    final query = _database.select(_database.tags)
      ..where((tag) => tag.isDeleted.equals(false))
      ..orderBy([(tag) => OrderingTerm.asc(tag.name)]);
    return query.watch();
  }

  Stream<List<String>> watchTagBookIds(String tagId) {
    final query = _database.select(_database.bookTagEntries)
      ..where((entry) => entry.tagId.equals(tagId))
      ..orderBy([(entry) => OrderingTerm.asc(entry.updatedAt)]);
    return query.watch().map(
      (entries) => entries.map((entry) => entry.bookId).toList(growable: false),
    );
  }

  Stream<List<ReadingProgressRecord>> watchReadingProgresses() {
    return _database.select(_database.readingProgresses).watch();
  }

  Stream<List<ReadingSessionRecord>> watchReadingSessions() {
    final query = _database.select(_database.readingSessions)
      ..where((session) => session.isDeleted.equals(false))
      ..orderBy([(session) => OrderingTerm.desc(session.startedAt)]);
    return query.watch();
  }

  Future<Set<String>> listBookTagIds(String bookId) async {
    final query =
        _database.select(_database.bookTagEntries).join([
          innerJoin(
            _database.tags,
            _database.tags.id.equalsExp(_database.bookTagEntries.tagId),
          ),
        ])..where(
          _database.bookTagEntries.bookId.equals(bookId) &
              _database.tags.isDeleted.equals(false),
        );
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(_database.bookTagEntries).tagId)
        .toSet();
  }

  Stream<List<String>> watchBookshelfBookIds(String bookshelfId) {
    final query = _database.select(_database.bookshelfEntries)
      ..where((entry) => entry.bookshelfId.equals(bookshelfId))
      ..orderBy([(entry) => OrderingTerm.asc(entry.sortOrder)]);
    return query.watch().map(
      (entries) => entries.map((entry) => entry.bookId).toList(growable: false),
    );
  }

  Future<Set<String>> listBookBookshelfIds(String bookId) async {
    final query =
        _database.select(_database.bookshelfEntries).join([
          innerJoin(
            _database.bookshelves,
            _database.bookshelves.id.equalsExp(
              _database.bookshelfEntries.bookshelfId,
            ),
          ),
        ])..where(
          _database.bookshelfEntries.bookId.equals(bookId) &
              _database.bookshelves.isDeleted.equals(false),
        );
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(_database.bookshelfEntries).bookshelfId)
        .toSet();
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

  Future<List<ExcerptRecord>> listExcerpts({String? bookId}) {
    final query = _database.select(_database.excerpts)
      ..where((excerpt) {
        final visible = excerpt.isDeleted.equals(false);
        return bookId == null
            ? visible
            : visible & excerpt.bookId.equals(bookId);
      })
      ..orderBy([
        (excerpt) => OrderingTerm.asc(excerpt.bookId),
        (excerpt) => OrderingTerm.asc(excerpt.createdAt),
      ]);
    return query.get();
  }

  Future<ReadingProgressRecord?> getReadingProgress(String bookId) {
    return (_database.select(
      _database.readingProgresses,
    )..where((progress) => progress.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<void> recordReadingSession({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final start = startedAt.toUtc();
    final end = endedAt.toUtc();
    if (end.isBefore(start)) {
      throw ArgumentError.value(endedAt, 'endedAt', 'Must follow startedAt.');
    }
    final duration = end.difference(start).inSeconds;
    if (duration < 1) return;
    final id = _idGenerator();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': id,
      'bookId': bookId,
      'deviceId': _deviceId,
      'startedAt': start.toIso8601String(),
      'endedAt': end.toIso8601String(),
      'durationSeconds': duration,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              id: id,
              bookId: bookId,
              deviceId: _deviceId,
              startedAt: start,
              endedAt: end,
              durationSeconds: duration,
              updatedAt: end,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.readingSession,
        entityId: id,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: end,
      );
    });
  }

  Future<void> updateReadingSession({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final current = await (_database.select(
      _database.readingSessions,
    )..where((session) => session.id.equals(sessionId))).getSingleOrNull();
    if (current == null || current.isDeleted) {
      throw StateError('Reading session $sessionId does not exist.');
    }
    final start = startedAt.toUtc();
    final end = endedAt.toUtc();
    final duration = end.difference(start).inSeconds;
    if (duration < 1) {
      throw ArgumentError.value(endedAt, 'endedAt', 'Session is too short.');
    }
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'bookId': current.bookId,
      'deviceId': current.deviceId,
      'startedAt': start.toIso8601String(),
      'endedAt': end.toIso8601String(),
      'durationSeconds': duration,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.readingSessions,
      )..where((session) => session.id.equals(sessionId))).write(
        ReadingSessionsCompanion(
          startedAt: Value(start),
          endedAt: Value(end),
          durationSeconds: Value(duration),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.readingSession,
        entityId: sessionId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  Future<void> deleteReadingSession(String sessionId) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      final affected =
          await (_database.update(_database.readingSessions)..where(
                (session) =>
                    session.id.equals(sessionId) &
                    session.isDeleted.equals(false),
              ))
              .write(
                ReadingSessionsCompanion(
                  isDeleted: const Value(true),
                  updatedAt: Value(now),
                ),
              );
      if (affected != 1) {
        throw StateError('Reading session $sessionId does not exist.');
      }
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.readingSession,
        entityId: sessionId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
  }

  Future<void> restoreReadingSession(ReadingSessionRecord session) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': session.id,
      'bookId': session.bookId,
      'deviceId': session.deviceId,
      'startedAt': session.startedAt.toUtc().toIso8601String(),
      'endedAt': session.endedAt.toUtc().toIso8601String(),
      'durationSeconds': session.durationSeconds,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.readingSessions,
      )..where((item) => item.id.equals(session.id))).write(
        ReadingSessionsCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.readingSession,
        entityId: session.id,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
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
    String? md5,
    required String title,
    required String mediaType,
    String? author,
    String? description,
    String? filePath,
    String? coverPath,
    String? coverSha256,
  }) async {
    final normalizedHash = sha256.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizedHash)) {
      throw ArgumentError.value(sha256, 'sha256', 'Expected 64 hex digits.');
    }
    final normalizedMd5 = md5?.toLowerCase();
    if (normalizedMd5 != null &&
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(normalizedMd5)) {
      throw ArgumentError.value(md5, 'md5', 'Expected 32 hex digits.');
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
            md5: normalizedMd5 == null
                ? const Value.absent()
                : Value(normalizedMd5),
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
      'md5': normalizedMd5,
      'title': title,
      'author': author,
      'description': description,
      'mediaType': mediaType,
      'coverSha256': coverSha256,
      'rating': null,
    };

    await _database.transaction(() async {
      await _database
          .into(_database.books)
          .insert(
            BooksCompanion.insert(
              id: bookId,
              sha256: normalizedHash,
              md5: Value(normalizedMd5),
              title: title,
              author: Value(author),
              description: Value(description),
              mediaType: mediaType,
              filePath: Value(filePath),
              coverPath: Value(coverPath),
              coverSha256: Value(coverSha256),
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
    await _updateBookDetails(
      current: current,
      title: title,
      author: author,
      description: description,
      rating: current.rating,
    );
  }

  Future<void> updateBookMd5({
    required String bookId,
    required String md5,
  }) async {
    final current = await getBook(bookId);
    if (current == null || current.isDeleted) {
      throw StateError('Book $bookId does not exist.');
    }
    final normalized = md5.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(normalized)) {
      throw ArgumentError.value(md5, 'md5', 'Expected 32 hex digits.');
    }
    if (current.md5 == normalized) return;
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'sha256': current.sha256,
      'md5': normalized,
      'title': current.title,
      'author': current.author,
      'description': current.description,
      'mediaType': current.mediaType,
      'coverSha256': current.coverSha256,
      'rating': current.rating,
    };
    await _database.transaction(() async {
      await (_database.update(_database.books)
            ..where((book) => book.id.equals(bookId)))
          .write(BooksCompanion(md5: Value(normalized), updatedAt: Value(now)));
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

  Future<void> updateBookDetails({
    required String bookId,
    required String title,
    required String? author,
    required String? description,
    required double? rating,
  }) async {
    final current = await getBook(bookId);
    if (current == null) throw StateError('Book $bookId does not exist.');
    if (rating != null && (rating < 0 || rating > 5)) {
      throw ArgumentError.value(
        rating,
        'rating',
        'Expected a value from 0 to 5.',
      );
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Book title is empty.');
    }
    final normalizedTitle = title.trim();
    final normalizedAuthor = author?.trim().isEmpty ?? true
        ? null
        : author!.trim();
    final normalizedDescription = description?.trim().isEmpty ?? true
        ? null
        : description!.trim();
    if (current.title == normalizedTitle &&
        current.author == normalizedAuthor &&
        current.description == normalizedDescription &&
        current.rating == rating) {
      return;
    }
    await _updateBookDetails(
      current: current,
      title: normalizedTitle,
      author: normalizedAuthor,
      description: normalizedDescription,
      rating: rating,
    );
  }

  Future<void> _updateBookDetails({
    required BookRecord current,
    required String title,
    required String? author,
    required String? description,
    required double? rating,
  }) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'sha256': current.sha256,
      'md5': current.md5,
      'title': title,
      'author': author,
      'description': description,
      'mediaType': current.mediaType,
      'coverSha256': current.coverSha256,
      'rating': rating,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.books,
      )..where((book) => book.id.equals(current.id))).write(
        BooksCompanion(
          title: Value(title),
          author: Value(author),
          description: Value(description),
          rating: Value(rating),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.book,
        entityId: current.id,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  Future<String> createTag({required String name, required int color}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name is empty.');
    }
    final duplicate =
        await (_database.select(_database.tags)..where(
              (tag) =>
                  tag.name.lower().equals(normalizedName.toLowerCase()) &
                  tag.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (duplicate != null) return duplicate.id;
    final tagId = _idGenerator();
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': tagId,
      'name': normalizedName,
      'color': color,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.tags)
          .insert(
            TagsCompanion.insert(
              id: tagId,
              name: normalizedName,
              color: color,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.tag,
        entityId: tagId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
    return tagId;
  }

  Future<void> updateTag({
    required String tagId,
    required String name,
    required int color,
  }) async {
    final current = await _requireVisibleTag(tagId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name is empty.');
    }
    if (current.name == normalizedName && current.color == color) return;
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': tagId,
      'name': normalizedName,
      'color': color,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.tags,
      )..where((tag) => tag.id.equals(tagId))).write(
        TagsCompanion(
          name: Value(normalizedName),
          color: Value(color),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.tag,
        entityId: tagId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  Future<void> deleteTag(String tagId) async {
    await _requireVisibleTag(tagId);
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.update(
        _database.tags,
      )..where((tag) => tag.id.equals(tagId))).write(
        TagsCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.tag,
        entityId: tagId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
  }

  Future<void> addBookTag({
    required String tagId,
    required String bookId,
  }) async {
    await _requireVisibleTag(tagId);
    final book = await getBook(bookId);
    if (book == null || book.isDeleted) {
      throw StateError('Book $bookId does not exist.');
    }
    final existing =
        await (_database.select(_database.bookTagEntries)..where(
              (entry) =>
                  entry.tagId.equals(tagId) & entry.bookId.equals(bookId),
            ))
            .getSingleOrNull();
    if (existing != null) return;
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{'tagId': tagId, 'bookId': bookId};
    await _database.transaction(() async {
      await _database
          .into(_database.bookTagEntries)
          .insert(
            BookTagEntriesCompanion.insert(
              tagId: tagId,
              bookId: bookId,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookTag,
        entityId: _bookTagId(tagId, bookId),
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  Future<void> removeBookTag({
    required String tagId,
    required String bookId,
  }) async {
    final existing =
        await (_database.select(_database.bookTagEntries)..where(
              (entry) =>
                  entry.tagId.equals(tagId) & entry.bookId.equals(bookId),
            ))
            .getSingleOrNull();
    if (existing == null) return;
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.delete(_database.bookTagEntries)..where(
            (entry) => entry.tagId.equals(tagId) & entry.bookId.equals(bookId),
          ))
          .go();
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookTag,
        entityId: _bookTagId(tagId, bookId),
        kind: OperationKind.delete,
        payload: {'tagId': tagId, 'bookId': bookId},
        occurredAt: now,
      );
    });
  }

  Future<TagRecord> _requireVisibleTag(String tagId) async {
    final tag =
        await (_database.select(_database.tags)..where(
              (row) => row.id.equals(tagId) & row.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (tag == null) throw StateError('Tag $tagId does not exist.');
    return tag;
  }

  static String _bookTagId(String tagId, String bookId) => '$tagId--$bookId';

  Future<String> createBookshelf({
    required String name,
    String? parentId,
    int sortOrder = 0,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Bookshelf name is empty.');
    }
    if (parentId != null) await _requireVisibleBookshelf(parentId);
    final bookshelfId = _idGenerator();
    final operationId = _idGenerator();
    final now = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'id': bookshelfId,
      'parentId': parentId,
      'name': normalizedName,
      'sortOrder': sortOrder,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.bookshelves)
          .insert(
            BookshelvesCompanion.insert(
              id: bookshelfId,
              parentId: Value(parentId),
              name: normalizedName,
              sortOrder: Value(sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookshelf,
        entityId: bookshelfId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
    return bookshelfId;
  }

  Future<void> renameBookshelf(String bookshelfId, String name) async {
    final current = await _requireVisibleBookshelf(bookshelfId);
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Bookshelf name is empty.');
    }
    if (current.name == normalizedName) return;
    await _upsertBookshelf(
      current,
      name: normalizedName,
      parentId: current.parentId,
      sortOrder: current.sortOrder,
    );
  }

  Future<void> moveBookshelf({
    required String bookshelfId,
    String? parentId,
    int? sortOrder,
  }) async {
    final current = await _requireVisibleBookshelf(bookshelfId);
    if (parentId == bookshelfId) {
      throw ArgumentError.value(
        parentId,
        'parentId',
        'A shelf cannot contain itself.',
      );
    }
    if (parentId != null) {
      await _requireVisibleBookshelf(parentId);
      String? cursor = parentId;
      while (cursor != null) {
        final currentCursor = cursor;
        if (currentCursor == bookshelfId) {
          throw ArgumentError.value(
            parentId,
            'parentId',
            'Moving the shelf would create a cycle.',
          );
        }
        final parent = await (_database.select(
          _database.bookshelves,
        )..where((shelf) => shelf.id.equals(currentCursor))).getSingleOrNull();
        cursor = parent?.parentId;
      }
    }
    final nextOrder = sortOrder ?? current.sortOrder;
    if (current.parentId == parentId && current.sortOrder == nextOrder) return;
    await _upsertBookshelf(
      current,
      name: current.name,
      parentId: parentId,
      sortOrder: nextOrder,
    );
  }

  Future<void> deleteBookshelf(String bookshelfId) async {
    await _requireVisibleBookshelf(bookshelfId);
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      await (_database.update(
        _database.bookshelves,
      )..where((shelf) => shelf.id.equals(bookshelfId))).write(
        BookshelvesCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
        ),
      );
      await (_database.update(
        _database.bookshelves,
      )..where((shelf) => shelf.parentId.equals(bookshelfId))).write(
        BookshelvesCompanion(
          parentId: const Value(null),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookshelf,
        entityId: bookshelfId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
  }

  Future<void> addBookToBookshelf({
    required String bookshelfId,
    required String bookId,
    int sortOrder = 0,
  }) async {
    await _requireVisibleBookshelf(bookshelfId);
    final book = await getBook(bookId);
    if (book == null || book.isDeleted) {
      throw StateError('Book $bookId does not exist.');
    }
    final existing =
        await (_database.select(_database.bookshelfEntries)..where(
              (entry) =>
                  entry.bookshelfId.equals(bookshelfId) &
                  entry.bookId.equals(bookId),
            ))
            .getSingleOrNull();
    if (existing != null && existing.sortOrder == sortOrder) return;
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final entityId = _bookshelfEntryId(bookshelfId, bookId);
    final payload = <String, Object?>{
      'bookshelfId': bookshelfId,
      'bookId': bookId,
      'sortOrder': sortOrder,
    };
    await _database.transaction(() async {
      await _database
          .into(_database.bookshelfEntries)
          .insertOnConflictUpdate(
            BookshelfEntriesCompanion.insert(
              bookshelfId: bookshelfId,
              bookId: bookId,
              sortOrder: Value(sortOrder),
              updatedAt: now,
            ),
          );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookshelfEntry,
        entityId: entityId,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  Future<void> removeBookFromBookshelf({
    required String bookshelfId,
    required String bookId,
  }) async {
    final existing =
        await (_database.select(_database.bookshelfEntries)..where(
              (entry) =>
                  entry.bookshelfId.equals(bookshelfId) &
                  entry.bookId.equals(bookId),
            ))
            .getSingleOrNull();
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      await (_database.delete(_database.bookshelfEntries)..where(
            (entry) =>
                entry.bookshelfId.equals(bookshelfId) &
                entry.bookId.equals(bookId),
          ))
          .go();
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookshelfEntry,
        entityId: _bookshelfEntryId(bookshelfId, bookId),
        kind: OperationKind.delete,
        payload: {'bookshelfId': bookshelfId, 'bookId': bookId},
        occurredAt: now,
      );
    });
  }

  Future<BookshelfRecord> _requireVisibleBookshelf(String bookshelfId) async {
    final shelf =
        await (_database.select(_database.bookshelves)..where(
              (row) => row.id.equals(bookshelfId) & row.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (shelf == null) {
      throw StateError('Bookshelf $bookshelfId does not exist.');
    }
    return shelf;
  }

  Future<void> _upsertBookshelf(
    BookshelfRecord current, {
    required String name,
    required String? parentId,
    required int sortOrder,
  }) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'parentId': parentId,
      'name': name,
      'sortOrder': sortOrder,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.bookshelves,
      )..where((shelf) => shelf.id.equals(current.id))).write(
        BookshelvesCompanion(
          parentId: Value(parentId),
          name: Value(name),
          sortOrder: Value(sortOrder),
          updatedAt: Value(now),
        ),
      );
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookshelf,
        entityId: current.id,
        kind: OperationKind.upsert,
        payload: payload,
        occurredAt: now,
      );
    });
  }

  static String _bookshelfEntryId(String bookshelfId, String bookId) =>
      '$bookshelfId--$bookId';

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

  Future<void> updateExcerpt({
    required String excerptId,
    required String note,
    required String color,
  }) async {
    final current =
        await (_database.select(_database.excerpts)..where(
              (excerpt) =>
                  excerpt.id.equals(excerptId) &
                  excerpt.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (current == null) throw StateError('Excerpt $excerptId does not exist.');
    final normalizedNote = note.trim().isEmpty ? null : note.trim();
    if (current.note == normalizedNote && current.color == color) return;
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'bookId': current.bookId,
      'locator': current.locator,
      'quote': current.quote,
      'note': normalizedNote,
      'color': color,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.excerpts,
      )..where((excerpt) => excerpt.id.equals(excerptId))).write(
        ExcerptsCompanion(
          note: Value(normalizedNote),
          color: Value(color),
          updatedAt: Value(now),
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
  }

  Future<void> deleteExcerpt(String excerptId) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      final affected =
          await (_database.update(_database.excerpts)..where(
                (excerpt) =>
                    excerpt.id.equals(excerptId) &
                    excerpt.isDeleted.equals(false),
              ))
              .write(
                ExcerptsCompanion(
                  isDeleted: const Value(true),
                  updatedAt: Value(now),
                ),
              );
      if (affected != 1) throw StateError('Excerpt $excerptId does not exist.');
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.excerpt,
        entityId: excerptId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
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

  Future<void> updateBookmark({
    required String bookmarkId,
    required String title,
    required String note,
  }) async {
    final current =
        await (_database.select(_database.bookmarks)..where(
              (bookmark) =>
                  bookmark.id.equals(bookmarkId) &
                  bookmark.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (current == null) {
      throw StateError('Bookmark $bookmarkId does not exist.');
    }
    final normalizedTitle = title.trim().isEmpty ? null : title.trim();
    final normalizedNote = note.trim().isEmpty ? null : note.trim();
    if (current.title == normalizedTitle && current.note == normalizedNote) {
      return;
    }
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'bookId': current.bookId,
      'locator': current.locator,
      'title': normalizedTitle,
      'note': normalizedNote,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.bookmarks,
      )..where((bookmark) => bookmark.id.equals(bookmarkId))).write(
        BookmarksCompanion(
          title: Value(normalizedTitle),
          note: Value(normalizedNote),
          updatedAt: Value(now),
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
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    await _database.transaction(() async {
      final affected =
          await (_database.update(_database.bookmarks)..where(
                (bookmark) =>
                    bookmark.id.equals(bookmarkId) &
                    bookmark.isDeleted.equals(false),
              ))
              .write(
                BookmarksCompanion(
                  isDeleted: const Value(true),
                  updatedAt: Value(now),
                ),
              );
      if (affected != 1) {
        throw StateError('Bookmark $bookmarkId does not exist.');
      }
      await _appendOperation(
        operationId: operationId,
        entityType: EntityType.bookmark,
        entityId: bookmarkId,
        kind: OperationKind.delete,
        payload: const {},
        occurredAt: now,
      );
    });
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

  Future<void> attachLocalCoverFile({
    required String bookId,
    required String coverPath,
  }) async {
    final affected =
        await (_database.update(_database.books)
              ..where((book) => book.id.equals(bookId)))
            .write(BooksCompanion(coverPath: Value(coverPath)));
    if (affected != 1) throw StateError('Book $bookId does not exist.');
  }

  Future<void> detachLocalBookFile(String bookId) async {
    final affected =
        await (_database.update(
          _database.books,
        )..where((book) => book.id.equals(bookId))).write(
          const BooksCompanion(
            filePath: Value(null),
            isAvailableLocally: Value(false),
          ),
        );
    if (affected != 1) throw StateError('Book $bookId does not exist.');
  }

  Future<void> replaceBookFile({
    required String bookId,
    required String sha256,
    String? md5,
    required String mediaType,
    required String filePath,
  }) async {
    final current = await getBook(bookId);
    if (current == null) throw StateError('Book $bookId does not exist.');
    final normalizedHash = sha256.toLowerCase();
    final normalizedMd5 = md5?.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizedHash)) {
      throw ArgumentError.value(sha256, 'sha256', 'Expected 64 hex digits.');
    }
    final duplicate =
        await (_database.select(_database.books)..where(
              (book) =>
                  book.sha256.equals(normalizedHash) &
                  book.id.equals(bookId).not(),
            ))
            .getSingleOrNull();
    if (duplicate != null) {
      throw StateError('The replacement is already stored as another book.');
    }

    final now = DateTime.now().toUtc();
    final operationId = _idGenerator();
    final payload = <String, Object?>{
      'id': current.id,
      'sha256': normalizedHash,
      'md5': normalizedMd5,
      'title': current.title,
      'author': current.author,
      'description': current.description,
      'mediaType': mediaType,
      'coverSha256': current.coverSha256,
      'rating': current.rating,
    };
    await _database.transaction(() async {
      await (_database.update(
        _database.books,
      )..where((book) => book.id.equals(bookId))).write(
        BooksCompanion(
          sha256: Value(normalizedHash),
          md5: Value(normalizedMd5),
          mediaType: Value(mediaType),
          filePath: Value(filePath),
          isAvailableLocally: const Value(true),
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
                  md5: Value(payload['md5'] as String?),
                  title: payload['title']! as String,
                  author: Value(payload['author'] as String?),
                  description: Value(payload['description'] as String?),
                  mediaType: payload['mediaType']! as String,
                  coverSha256: Value(payload['coverSha256'] as String?),
                  rating: Value((payload['rating'] as num?)?.toDouble()),
                  isAvailableLocally: const Value(false),
                  createdAt: operation.occurredAt.toUtc(),
                  updatedAt: operation.occurredAt.toUtc(),
                ),
              );
        } else {
          final remoteHash = payload['sha256']! as String;
          final hashChanged = existing.sha256 != remoteHash;
          final remoteCoverHash = payload['coverSha256'] as String?;
          final coverChanged = existing.coverSha256 != remoteCoverHash;
          await (_database.update(
            _database.books,
          )..where((book) => book.id.equals(operation.entityId))).write(
            BooksCompanion(
              sha256: Value(remoteHash),
              md5: payload.containsKey('md5')
                  ? Value(payload['md5'] as String?)
                  : const Value.absent(),
              title: Value(payload['title']! as String),
              author: Value(payload['author'] as String?),
              description: Value(payload['description'] as String?),
              mediaType: Value(payload['mediaType']! as String),
              coverSha256: Value(remoteCoverHash),
              coverPath: coverChanged
                  ? const Value(null)
                  : const Value.absent(),
              rating: Value((payload['rating'] as num?)?.toDouble()),
              filePath: hashChanged ? const Value(null) : const Value.absent(),
              isAvailableLocally: hashChanged
                  ? const Value(false)
                  : const Value.absent(),
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
      case EntityType.readingSession:
        if (deleted) {
          await (_database.update(
            _database.readingSessions,
          )..where((session) => session.id.equals(operation.entityId))).write(
            ReadingSessionsCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          return;
        }
        await _database
            .into(_database.readingSessions)
            .insertOnConflictUpdate(
              ReadingSessionsCompanion.insert(
                id: operation.entityId,
                bookId: payload['bookId']! as String,
                deviceId: payload['deviceId'] as String? ?? operation.deviceId,
                startedAt: DateTime.parse(payload['startedAt']! as String),
                endedAt: DateTime.parse(payload['endedAt']! as String),
                durationSeconds: payload['durationSeconds']! as int,
                isDeleted: const Value(false),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.bookshelf:
        if (deleted) {
          await (_database.update(
            _database.bookshelves,
          )..where((shelf) => shelf.id.equals(operation.entityId))).write(
            BookshelvesCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          await (_database.update(
            _database.bookshelves,
          )..where((shelf) => shelf.parentId.equals(operation.entityId))).write(
            BookshelvesCompanion(
              parentId: const Value(null),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          return;
        }
        await _database
            .into(_database.bookshelves)
            .insertOnConflictUpdate(
              BookshelvesCompanion.insert(
                id: operation.entityId,
                parentId: Value(payload['parentId'] as String?),
                name: payload['name']! as String,
                sortOrder: Value(payload['sortOrder'] as int? ?? 0),
                isDeleted: const Value(false),
                createdAt: operation.occurredAt.toUtc(),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.bookshelfEntry:
        final bookshelfId = payload['bookshelfId']! as String;
        final bookId = payload['bookId']! as String;
        if (deleted) {
          await (_database.delete(_database.bookshelfEntries)..where(
                (entry) =>
                    entry.bookshelfId.equals(bookshelfId) &
                    entry.bookId.equals(bookId),
              ))
              .go();
          return;
        }
        await _database
            .into(_database.bookshelfEntries)
            .insertOnConflictUpdate(
              BookshelfEntriesCompanion.insert(
                bookshelfId: bookshelfId,
                bookId: bookId,
                sortOrder: Value(payload['sortOrder'] as int? ?? 0),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.tag:
        if (deleted) {
          await (_database.update(
            _database.tags,
          )..where((tag) => tag.id.equals(operation.entityId))).write(
            TagsCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(operation.occurredAt.toUtc()),
            ),
          );
          return;
        }
        await _database
            .into(_database.tags)
            .insertOnConflictUpdate(
              TagsCompanion.insert(
                id: operation.entityId,
                name: payload['name']! as String,
                color: payload['color']! as int,
                isDeleted: const Value(false),
                createdAt: operation.occurredAt.toUtc(),
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
        return;
      case EntityType.bookTag:
        final tagId = payload['tagId']! as String;
        final bookId = payload['bookId']! as String;
        if (deleted) {
          await (_database.delete(_database.bookTagEntries)..where(
                (entry) =>
                    entry.tagId.equals(tagId) & entry.bookId.equals(bookId),
              ))
              .go();
          return;
        }
        await _database
            .into(_database.bookTagEntries)
            .insertOnConflictUpdate(
              BookTagEntriesCompanion.insert(
                tagId: tagId,
                bookId: bookId,
                updatedAt: operation.occurredAt.toUtc(),
              ),
            );
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
