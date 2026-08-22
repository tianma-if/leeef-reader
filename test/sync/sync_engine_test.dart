import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:leeef_reader/src/sync/sync_operation.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase databaseA;
  late AppDatabase databaseB;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leeef-sync-engine-',
    );
    databaseA = AppDatabase.forTesting(NativeDatabase.memory());
    databaseB = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await databaseA.close();
    await databaseB.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'two devices exchange book file, excerpt, and reading progress',
    () async {
      final repositoryA = LibraryRepository(
        database: databaseA,
        deviceId: 'device-a',
        idGenerator: _Ids([
          'book-1',
          'op-book',
          'excerpt-1',
          'op-excerpt',
        ]).next,
      );
      final repositoryB = LibraryRepository(
        database: databaseB,
        deviceId: 'device-b',
        idGenerator: _Ids(['op-progress']).next,
      );
      final source = File('${temporaryDirectory.path}/source.epub');
      await source.writeAsString('cross-device-book');
      final imported = await BookImportService(
        repository: repositoryA,
        libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
      ).importFile(source);
      await repositoryA.createExcerpt(
        bookId: imported.id,
        locator: 'epubcfi(/6/2!/4/2:0)',
        quote: 'Shared quote',
      );

      final backend = DirectorySyncBackend(
        Directory('${temporaryDirectory.path}/remote'),
      );
      final engineA = SyncEngine(
        repository: repositoryA,
        backend: backend,
        libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
      );
      final engineB = SyncEngine(
        repository: repositoryB,
        backend: backend,
        libraryDirectory: Directory('${temporaryDirectory.path}/device-b'),
      );

      expect((await engineA.synchronize()).uploadedOperations, 2);
      final firstPull = await engineB.synchronize();
      expect(firstPull.downloadedOperations, 2);
      expect(firstPull.downloadedBooks, 1);
      final remoteBook = await repositoryB.getBook('book-1');
      expect(remoteBook?.isAvailableLocally, isTrue);
      expect(
        await File(remoteBook!.filePath!).readAsString(),
        'cross-device-book',
      );
      expect(await databaseB.select(databaseB.excerpts).get(), hasLength(1));

      await repositoryB.updateReadingProgress(
        bookId: 'book-1',
        location: const ReadingLocation(
          locator: 'epubcfi(/6/4!/4/2:0)',
          progress: 0.75,
          chapterTitle: 'Chapter 2',
        ),
      );
      await engineB.synchronize();
      await engineA.synchronize();
      expect((await repositoryA.getReadingProgress('book-1'))?.progress, 0.75);
    },
  );

  test('backend failure leaves operation pending for retry', () async {
    final repository = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids(['book-1', 'op-book']).next,
    );
    await repository.createBookMetadata(
      sha256: 'a' * 64,
      title: 'Offline Book',
      mediaType: 'application/epub+zip',
    );
    final engine = SyncEngine(
      repository: repository,
      backend: _OfflineBackend(),
      libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
    );

    await expectLater(engine.synchronize(), throwsA(isA<SyncUnavailable>()));
    expect(await repository.pendingSyncOperations(), hasLength(1));
  });
}

class _OfflineBackend implements SyncBackend {
  @override
  Future<void> appendOperation(SyncOperation operation) {
    throw const SyncUnavailable('offline');
  }

  @override
  Future<void> downloadBlob(String sha256, File destination) {
    throw const SyncUnavailable('offline');
  }

  @override
  Future<bool> hasBlob(String sha256) async => false;

  @override
  Future<List<SyncOperation>> listOperations() async => const [];

  @override
  Future<void> uploadBlob(String sha256, File source) {
    throw const SyncUnavailable('offline');
  }
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
