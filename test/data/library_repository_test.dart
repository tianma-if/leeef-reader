import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('book mutation and sync operation commit atomically', () async {
    final ids = _Ids(['book-1', 'op-create']);
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: ids.next,
    );

    final bookId = await repository.createBookMetadata(
      sha256: 'a' * 64,
      title: 'Test Book',
      mediaType: 'application/epub+zip',
    );

    expect(bookId, 'book-1');
    expect(await database.select(database.books).get(), hasLength(1));
    final operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(1));
    expect(operations.single.entityId, 'book-1');
    expect(operations.single.kind, 'upsert');
  });

  test('duplicate content hash reuses the stable book ID', () async {
    final ids = _Ids(['book-1', 'op-create']);
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: ids.next,
    );

    final first = await repository.createBookMetadata(
      sha256: 'b' * 64,
      title: 'First title',
      mediaType: 'application/epub+zip',
    );
    final duplicate = await repository.createBookMetadata(
      sha256: 'b' * 64,
      title: 'Duplicate title',
      mediaType: 'application/epub+zip',
    );

    expect(duplicate, first);
    expect(await database.select(database.books).get(), hasLength(1));
    expect(await database.select(database.syncOperations).get(), hasLength(1));
  });

  test('reading progress keeps current state and per-device history', () async {
    final ids = _Ids(['book-1', 'op-create', 'op-progress']);
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: ids.next,
    );
    await repository.createBookMetadata(
      sha256: 'c' * 64,
      title: 'Progress Book',
      mediaType: 'application/epub+zip',
    );

    await repository.updateReadingProgress(
      bookId: 'book-1',
      location: const ReadingLocation(
        locator: 'epubcfi(/6/2!/4/2:0)',
        progress: 0.25,
        chapterTitle: 'Chapter 1',
      ),
    );

    final current = await database
        .select(database.readingProgresses)
        .getSingle();
    final history = await database
        .select(database.readingProgressHistory)
        .getSingle();
    expect(current.progress, 0.25);
    expect(history.operationId, 'op-progress');
    expect(history.deviceId, 'device-a');
  });

  test('operation-log failure rolls back the business mutation', () async {
    final ids = _Ids(['book-1', 'same-op', 'book-2', 'same-op']);
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: ids.next,
    );
    await repository.createBookMetadata(
      sha256: 'd' * 64,
      title: 'Committed',
      mediaType: 'application/epub+zip',
    );

    await expectLater(
      repository.createBookMetadata(
        sha256: 'e' * 64,
        title: 'Must roll back',
        mediaType: 'application/epub+zip',
      ),
      throwsA(anything),
    );

    final books = await database.select(database.books).get();
    expect(books.map((book) => book.title), ['Committed']);
    expect(await database.select(database.syncOperations).get(), hasLength(1));
  });

  test('excerpt and bookmark mutations append sync operations', () async {
    final ids = _Ids([
      'book-1',
      'op-create',
      'excerpt-1',
      'op-excerpt',
      'bookmark-1',
      'op-bookmark',
    ]);
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: ids.next,
    );
    await repository.createBookMetadata(
      sha256: 'f' * 64,
      title: 'Annotated Book',
      mediaType: 'application/epub+zip',
    );

    await repository.createExcerpt(
      bookId: 'book-1',
      locator: 'epubcfi(/6/2!/4/2:0)',
      quote: 'A durable excerpt',
      note: 'Remember this',
    );
    await repository.createBookmark(
      bookId: 'book-1',
      locator: 'epubcfi(/6/4)',
      title: 'Chapter 2',
    );

    expect(await database.select(database.excerpts).get(), hasLength(1));
    expect(await database.select(database.bookmarks).get(), hasLength(1));
    final operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(3));
    expect(operations[1].entityType, 'excerpt');
    expect(operations[2].entityType, 'bookmark');
  });

  test('bookshelf lifecycle and membership append sync operations', () async {
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'shelf-1',
        'op-shelf',
        'op-add',
        'op-rename',
        'op-remove',
        'op-delete',
      ]).next,
    );
    await repository.createBookMetadata(
      sha256: '1' * 64,
      title: 'Organized Book',
      mediaType: 'application/epub+zip',
    );
    final shelfId = await repository.createBookshelf(name: ' Fiction ');
    await repository.addBookToBookshelf(bookshelfId: shelfId, bookId: 'book-1');

    expect(await repository.listBookBookshelfIds('book-1'), {'shelf-1'});
    expect(
      (await database.select(database.bookshelves).getSingle()).name,
      'Fiction',
    );

    await repository.renameBookshelf(shelfId, 'Novels');
    await repository.removeBookFromBookshelf(
      bookshelfId: shelfId,
      bookId: 'book-1',
    );
    await repository.deleteBookshelf(shelfId);

    expect(await repository.listBookBookshelfIds('book-1'), isEmpty);
    expect(
      (await database.select(database.bookshelves).getSingle()).isDeleted,
      isTrue,
    );
    final operations = await database.select(database.syncOperations).get();
    expect(operations.map((operation) => operation.entityType), [
      'book',
      'bookshelf',
      'bookshelfEntry',
      'bookshelf',
      'bookshelfEntry',
      'bookshelf',
    ]);
    expect(operations[4].kind, 'delete');
  });

  test('bookshelf hierarchy rejects cycles', () async {
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: _Ids(['parent', 'op-parent', 'child', 'op-child']).next,
    );
    await repository.createBookshelf(name: 'Parent');
    await repository.createBookshelf(name: 'Child', parentId: 'parent');

    await expectLater(
      repository.moveBookshelf(bookshelfId: 'parent', parentId: 'child'),
      throwsArgumentError,
    );
  });

  test('excerpt and bookmark support synced update and delete', () async {
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'excerpt-1',
        'op-excerpt',
        'bookmark-1',
        'op-bookmark',
        'op-update-excerpt',
        'op-update-bookmark',
        'op-delete-excerpt',
        'op-delete-bookmark',
      ]).next,
    );
    await repository.createBookMetadata(
      sha256: '3' * 64,
      title: 'Annotations',
      mediaType: 'application/epub+zip',
    );
    await repository.createExcerpt(
      bookId: 'book-1',
      locator: 'epubcfi(/6/2)',
      quote: 'Quote',
    );
    await repository.createBookmark(bookId: 'book-1', locator: 'epubcfi(/6/4)');

    await repository.updateExcerpt(
      excerptId: 'excerpt-1',
      note: 'Revised',
      color: 'blue',
    );
    await repository.updateBookmark(
      bookmarkId: 'bookmark-1',
      title: 'Chapter',
      note: 'Return here',
    );

    expect(
      (await database.select(database.excerpts).getSingle()).note,
      'Revised',
    );
    expect(
      (await database.select(database.excerpts).getSingle()).color,
      'blue',
    );
    expect(
      (await database.select(database.bookmarks).getSingle()).note,
      'Return here',
    );

    await repository.deleteExcerpt('excerpt-1');
    await repository.deleteBookmark('bookmark-1');
    expect(await repository.listExcerpts(), isEmpty);
    expect(await repository.watchBookmarks().first, isEmpty);
    final operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(7));
    expect(operations[5].kind, 'delete');
    expect(operations[6].kind, 'delete');
  });

  test('book details and tag membership are synced transactionally', () async {
    final repository = LibraryRepository(
      database: database,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'op-details',
        'tag-1',
        'op-tag',
        'op-add-tag',
        'op-update-tag',
        'op-remove-tag',
        'op-delete-tag',
      ]).next,
    );
    await repository.createBookMetadata(
      sha256: '5' * 64,
      title: 'Original',
      mediaType: 'application/epub+zip',
    );
    await repository.updateBookDetails(
      bookId: 'book-1',
      title: ' Revised ',
      author: ' Writer ',
      description: ' Description ',
      rating: 4.5,
    );
    final tagId = await repository.createTag(
      name: ' Fiction ',
      color: 0xFF336699,
    );
    await repository.addBookTag(tagId: tagId, bookId: 'book-1');

    final book = await repository.getBook('book-1');
    expect(book?.title, 'Revised');
    expect(book?.author, 'Writer');
    expect(book?.rating, 4.5);
    expect(await repository.listBookTagIds('book-1'), {'tag-1'});

    await repository.updateTag(tagId: tagId, name: 'Novel', color: 0xFF112233);
    expect((await database.select(database.tags).getSingle()).name, 'Novel');
    await repository.removeBookTag(tagId: tagId, bookId: 'book-1');
    await repository.deleteTag(tagId);

    expect(await repository.listBookTagIds('book-1'), isEmpty);
    expect(
      (await database.select(database.tags).getSingle()).isDeleted,
      isTrue,
    );
    final operations = await database.select(database.syncOperations).get();
    expect(operations.map((operation) => operation.entityType), [
      'book',
      'book',
      'tag',
      'bookTag',
      'tag',
      'bookTag',
      'tag',
    ]);
  });

  test(
    'reading sessions support synced create, edit, delete, and undo',
    () async {
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device-a',
        idGenerator: _Ids([
          'book-1',
          'op-book',
          'session-1',
          'op-session',
          'op-edit',
          'op-delete',
          'op-restore',
        ]).next,
      );
      await repository.createBookMetadata(
        sha256: '7' * 64,
        title: 'Timed book',
        mediaType: 'text/plain',
      );
      final start = DateTime.utc(2026, 8, 26, 10);
      await repository.recordReadingSession(
        bookId: 'book-1',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 12)),
      );
      var session = await database.select(database.readingSessions).getSingle();
      expect(session.durationSeconds, 720);

      await repository.updateReadingSession(
        sessionId: session.id,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 20)),
      );
      session = await database.select(database.readingSessions).getSingle();
      expect(session.durationSeconds, 1200);
      await repository.deleteReadingSession(session.id);
      expect(
        (await database.select(database.readingSessions).getSingle()).isDeleted,
        isTrue,
      );
      await repository.restoreReadingSession(session);
      expect(
        (await database.select(database.readingSessions).getSingle()).isDeleted,
        isFalse,
      );
      expect(
        await database.select(database.syncOperations).get(),
        hasLength(5),
      );
    },
  );
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
