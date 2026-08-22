import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase database;
  late BookImportService importer;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leeef-import-test-',
    );
    database = AppDatabase.forTesting(NativeDatabase.memory());
    importer = BookImportService(
      repository: LibraryRepository(
        database: database,
        deviceId: 'device-a',
        idGenerator: _Ids(['book-1', 'operation-1']).next,
      ),
      libraryDirectory: Directory('${temporaryDirectory.path}/library'),
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('copies EPUB into managed storage and persists its hash', () async {
    final source = File('${temporaryDirectory.path}/A Good Book.epub');
    await source.writeAsString('valid-enough-import-fixture');

    final book = await importer.importFile(source);

    expect(book.id, 'book-1');
    expect(book.title, 'A Good Book');
    expect(book.mediaType, 'application/epub+zip');
    expect(book.sha256, hasLength(64));
    expect(book.isAvailableLocally, isTrue);
    expect(
      await File(book.filePath!).readAsString(),
      source.readAsStringSync(),
    );
  });

  test('rejects unsupported files without changing the database', () async {
    final source = File('${temporaryDirectory.path}/notes.pdf');
    await source.writeAsString('pdf');

    await expectLater(
      importer.importFile(source),
      throwsA(isA<UnsupportedBookFormat>()),
    );
    expect(await database.select(database.books).get(), isEmpty);
  });

  test('repairs a corrupt managed copy when the book is re-imported', () async {
    final source = File('${temporaryDirectory.path}/Repair.epub');
    await source.writeAsString('original-content');
    final first = await importer.importFile(source);
    await File(first.filePath!).writeAsString('corrupt');

    final repaired = await importer.importFile(source);

    expect(repaired.id, first.id);
    expect(await File(repaired.filePath!).readAsString(), 'original-content');
    expect(await database.select(database.books).get(), hasLength(1));
  });
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
