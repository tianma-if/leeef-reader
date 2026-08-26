import 'dart:io';

import 'package:crypto/crypto.dart';
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

  test('book covers are stored as verified blobs and restored', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids(['book-1', 'op-book']).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
    );
    final bookBytes = 'book-content'.codeUnits;
    final coverBytes = 'cover-content'.codeUnits;
    final bookHash = sha256.convert(bookBytes).toString();
    final coverHash = sha256.convert(coverBytes).toString();
    final localA = Directory('${temporaryDirectory.path}/cover-a');
    await localA.create(recursive: true);
    final bookFile = File('${localA.path}/$bookHash.epub');
    final coverFile = File('${localA.path}/$coverHash.cover.png');
    await bookFile.writeAsBytes(bookBytes);
    await coverFile.writeAsBytes(coverBytes);
    await repositoryA.createBookMetadata(
      sha256: bookHash,
      title: 'Covered',
      mediaType: 'application/epub+zip',
      filePath: bookFile.path,
      coverPath: coverFile.path,
      coverSha256: coverHash,
    );
    final backend = DirectorySyncBackend(
      Directory('${temporaryDirectory.path}/cover-remote'),
    );
    await SyncEngine(
      repository: repositoryA,
      backend: backend,
      libraryDirectory: localA,
    ).synchronize();
    final report = await SyncEngine(
      repository: repositoryB,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/cover-b'),
    ).synchronize();

    final remote = await repositoryB.getBook('book-1');
    expect(report.downloadedBooks, 1);
    expect(report.downloadedCovers, 1);
    expect(remote?.coverSha256, coverHash);
    expect(await File(remote!.coverPath!).readAsBytes(), coverBytes);
  });

  test(
    'a replacement keeps the book ID and refreshes remote local files',
    () async {
      final repositoryA = LibraryRepository(
        database: databaseA,
        deviceId: 'device-a',
        idGenerator: _Ids(['book-1', 'op-book', 'op-replace']).next,
      );
      final repositoryB = LibraryRepository(
        database: databaseB,
        deviceId: 'device-b',
      );
      final directoryA = Directory('${temporaryDirectory.path}/replace-a');
      final directoryB = Directory('${temporaryDirectory.path}/replace-b');
      final importer = BookImportService(
        repository: repositoryA,
        libraryDirectory: directoryA,
      );
      final original = File('${temporaryDirectory.path}/original.epub');
      final replacement = File('${temporaryDirectory.path}/replacement.pdf');
      await original.writeAsString('old-book');
      await replacement.writeAsString('new-book');
      final book = await importer.importFile(original);
      final backend = DirectorySyncBackend(
        Directory('${temporaryDirectory.path}/replace-remote'),
      );
      final engineA = SyncEngine(
        repository: repositoryA,
        backend: backend,
        libraryDirectory: directoryA,
      );
      final engineB = SyncEngine(
        repository: repositoryB,
        backend: backend,
        libraryDirectory: directoryB,
      );
      await engineA.synchronize();
      await engineB.synchronize();

      final replaced = await importer.replaceFile(
        book: book,
        source: replacement,
      );
      await engineA.synchronize();
      final report = await engineB.synchronize();

      final remote = await repositoryB.getBook(book.id);
      expect(replaced.id, book.id);
      expect(remote?.id, book.id);
      expect(remote?.sha256, replaced.sha256);
      expect(remote?.mediaType, 'application/pdf');
      expect(remote?.filePath, endsWith('.pdf'));
      expect(await File(remote!.filePath!).readAsString(), 'new-book');
      expect(report.downloadedBooks, 1);
    },
  );

  test('two devices exchange bookshelf hierarchy and membership', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'shelf-1',
        'op-shelf',
        'op-entry',
      ]).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
    );
    await repositoryA.createBookMetadata(
      sha256: '2' * 64,
      title: 'Shelf Sync',
      mediaType: 'application/epub+zip',
    );
    await repositoryA.createBookshelf(name: 'Reading next');
    await repositoryA.addBookToBookshelf(
      bookshelfId: 'shelf-1',
      bookId: 'book-1',
    );
    final backend = DirectorySyncBackend(
      Directory('${temporaryDirectory.path}/remote'),
    );

    await SyncEngine(
      repository: repositoryA,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
    ).synchronize();
    final report = await SyncEngine(
      repository: repositoryB,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/device-b'),
    ).synchronize();

    expect(report.downloadedOperations, 3);
    expect(
      (await databaseB.select(databaseB.bookshelves).getSingle()).name,
      'Reading next',
    );
    expect(await repositoryB.listBookBookshelfIds('book-1'), {'shelf-1'});
  });

  test('annotation updates and tombstones converge across devices', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'excerpt-1',
        'op-excerpt',
        'bookmark-1',
        'op-bookmark',
      ]).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
      idGenerator: _Ids([
        'op-update-excerpt',
        'op-update-bookmark',
        'op-delete-excerpt',
        'op-delete-bookmark',
      ]).next,
    );
    await repositoryA.createBookMetadata(
      sha256: '4' * 64,
      title: 'Shared annotations',
      mediaType: 'application/epub+zip',
    );
    await repositoryA.createExcerpt(
      bookId: 'book-1',
      locator: 'epubcfi(/6/2)',
      quote: 'Original quote',
    );
    await repositoryA.createBookmark(
      bookId: 'book-1',
      locator: 'epubcfi(/6/4)',
    );
    final backend = DirectorySyncBackend(
      Directory('${temporaryDirectory.path}/annotation-remote'),
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
    await engineA.synchronize();
    await engineB.synchronize();

    await repositoryB.updateExcerpt(
      excerptId: 'excerpt-1',
      note: 'Synced note',
      color: 'green',
    );
    await repositoryB.updateBookmark(
      bookmarkId: 'bookmark-1',
      title: 'Synced title',
      note: '',
    );
    await engineB.synchronize();
    await engineA.synchronize();
    expect(
      (await databaseA.select(databaseA.excerpts).getSingle()).note,
      'Synced note',
    );
    expect(
      (await databaseA.select(databaseA.bookmarks).getSingle()).title,
      'Synced title',
    );

    await repositoryB.deleteExcerpt('excerpt-1');
    await repositoryB.deleteBookmark('bookmark-1');
    await engineB.synchronize();
    await engineA.synchronize();
    expect(
      (await databaseA.select(databaseA.excerpts).getSingle()).isDeleted,
      isTrue,
    );
    expect(
      (await databaseA.select(databaseA.bookmarks).getSingle()).isDeleted,
      isTrue,
    );
  });

  test('ratings, tags, and tag membership converge across devices', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids([
        'book-1',
        'op-book',
        'tag-1',
        'op-tag',
        'op-book-tag',
      ]).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
      idGenerator: _Ids([
        'op-book-details',
        'op-tag-update',
        'op-book-tag-remove',
      ]).next,
    );
    await repositoryA.createBookMetadata(
      sha256: '6' * 64,
      title: 'Tagged book',
      mediaType: 'application/epub+zip',
    );
    await repositoryA.createTag(name: 'Essay', color: 0xFF00AA00);
    await repositoryA.addBookTag(tagId: 'tag-1', bookId: 'book-1');
    final backend = DirectorySyncBackend(
      Directory('${temporaryDirectory.path}/tag-remote'),
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
    await engineA.synchronize();
    await engineB.synchronize();
    expect(await repositoryB.listBookTagIds('book-1'), {'tag-1'});

    await repositoryB.updateBookDetails(
      bookId: 'book-1',
      title: 'Tagged book',
      author: null,
      description: null,
      rating: 5,
    );
    await repositoryB.updateTag(
      tagId: 'tag-1',
      name: 'Essays',
      color: 0xFF0000AA,
    );
    await repositoryB.removeBookTag(tagId: 'tag-1', bookId: 'book-1');
    await engineB.synchronize();
    await engineA.synchronize();

    expect((await repositoryA.getBook('book-1'))?.rating, 5);
    expect((await databaseA.select(databaseA.tags).getSingle()).name, 'Essays');
    expect(await repositoryA.listBookTagIds('book-1'), isEmpty);
  });

  test('reading sessions converge and preserve edits across devices', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids(['book-1', 'op-book', 'session-1', 'op-session']).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
      idGenerator: _Ids(['op-edit']).next,
    );
    await repositoryA.createBookMetadata(
      sha256: '8' * 64,
      title: 'Statistics',
      mediaType: 'text/plain',
    );
    final backend = DirectorySyncBackend(
      Directory('${temporaryDirectory.path}/statistics-remote'),
    );
    final engineA = SyncEngine(
      repository: repositoryA,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/statistics-a'),
    );
    final engineB = SyncEngine(
      repository: repositoryB,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/statistics-b'),
    );
    await engineA.synchronize();
    await engineB.synchronize();
    final start = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await repositoryA.recordReadingSession(
      bookId: 'book-1',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 10)),
    );
    await engineA.synchronize();
    await engineB.synchronize();
    var remote = await databaseB.select(databaseB.readingSessions).getSingle();
    expect(remote.durationSeconds, 600);

    await repositoryB.updateReadingSession(
      sessionId: remote.id,
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 25)),
    );
    await engineB.synchronize();
    await engineA.synchronize();
    remote = await databaseA.select(databaseA.readingSessions).getSingle();
    expect(remote.durationSeconds, 1500);
  });

  for (final format in const [
    (extension: 'pdf', mediaType: 'application/pdf'),
    (extension: 'txt', mediaType: 'text/plain'),
    (extension: 'mobi', mediaType: 'application/x-mobipocket-ebook'),
    (extension: 'azw3', mediaType: 'application/vnd.amazon.ebook'),
    (extension: 'fb2', mediaType: 'application/x-fictionbook+xml'),
  ]) {
    test(
      'restores ${format.extension.toUpperCase()} with its original extension',
      () async {
        final repositoryA = LibraryRepository(
          database: databaseA,
          deviceId: 'device-a',
          idGenerator: _Ids(['book-1', 'op-book']).next,
        );
        final repositoryB = LibraryRepository(
          database: databaseB,
          deviceId: 'device-b',
        );
        final source = File(
          '${temporaryDirectory.path}/source.${format.extension}',
        );
        await source.writeAsString('synced-${format.extension}');
        final book = await BookImportService(
          repository: repositoryA,
          libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
        ).importFile(source);
        expect(book.mediaType, format.mediaType);

        final backend = DirectorySyncBackend(
          Directory('${temporaryDirectory.path}/remote'),
        );
        await SyncEngine(
          repository: repositoryA,
          backend: backend,
          libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
        ).synchronize();
        await SyncEngine(
          repository: repositoryB,
          backend: backend,
          libraryDirectory: Directory('${temporaryDirectory.path}/device-b'),
        ).synchronize();

        final restored = await repositoryB.getBook('book-1');
        expect(restored?.filePath, endsWith('.${format.extension}'));
        expect(
          await File(restored!.filePath!).readAsString(),
          'synced-${format.extension}',
        );
      },
    );
  }

  test('corrupt blob is rejected and a later retry recovers', () async {
    final repositoryA = LibraryRepository(
      database: databaseA,
      deviceId: 'device-a',
      idGenerator: _Ids(['book-1', 'op-book']).next,
    );
    final repositoryB = LibraryRepository(
      database: databaseB,
      deviceId: 'device-b',
    );
    final source = File('${temporaryDirectory.path}/source.epub');
    await source.writeAsString('integrity-protected-book');
    final book = await BookImportService(
      repository: repositoryA,
      libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
    ).importFile(source);
    final remote = Directory('${temporaryDirectory.path}/remote');
    final backend = DirectorySyncBackend(remote);
    await SyncEngine(
      repository: repositoryA,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/device-a'),
    ).synchronize();
    final remoteBlob = File('${remote.path}/blobs/${book.sha256}/original');
    await remoteBlob.writeAsString('corrupted');

    final engineB = SyncEngine(
      repository: repositoryB,
      backend: backend,
      libraryDirectory: Directory('${temporaryDirectory.path}/device-b'),
    );
    await expectLater(
      engineB.synchronize(),
      throwsA(isA<SyncIntegrityException>()),
    );
    expect((await repositoryB.getBook('book-1'))?.isAvailableLocally, isFalse);

    await remoteBlob.writeAsString('integrity-protected-book');
    final recovery = await engineB.synchronize();
    expect(recovery.downloadedBooks, 1);
    expect((await repositoryB.getBook('book-1'))?.isAvailableLocally, isTrue);
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
