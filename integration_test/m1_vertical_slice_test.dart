import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('M1 import, excerpt, file sync, and retry survive end to end', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('leeef-m1-e2e-');
    final databaseA = AppDatabase.forTesting(NativeDatabase.memory());
    final databaseB = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await databaseA.close();
      await databaseB.close();
      await root.delete(recursive: true);
    });
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids(['book-1', 'op-book', 'excerpt-1', 'op-excerpt']).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
    );
    final source = File('${root.path}/M1 Fixture.epub');
    await source.writeAsString('m1-cross-platform-payload');
    final imported = await BookImportService(
      repository: repositoryA,
      libraryDirectory: Directory('${root.path}/device-a'),
    ).importFile(source);
    await repositoryA.createExcerpt(
      bookId: imported.id,
      locator: 'epubcfi(/6/2!/4/2:0)',
      quote: 'Cross-platform excerpt',
    );

    final backend = DirectorySyncBackend(Directory('${root.path}/remote'));
    await SyncEngine(
      repository: repositoryA,
      backend: backend,
      libraryDirectory: Directory('${root.path}/device-a'),
    ).synchronize();
    final received = await SyncEngine(
      repository: repositoryB,
      backend: backend,
      libraryDirectory: Directory('${root.path}/device-b'),
    ).synchronize();

    expect(received.downloadedOperations, 2);
    expect(received.downloadedBooks, 1);
    expect(await databaseB.select(databaseB.excerpts).get(), hasLength(1));
    final book = await repositoryB.getBook(imported.id);
    expect(book?.isAvailableLocally, isTrue);
    expect(
      await File(book!.filePath!).readAsString(),
      'm1-cross-platform-payload',
    );
  });
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
