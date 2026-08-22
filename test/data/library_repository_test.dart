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
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
