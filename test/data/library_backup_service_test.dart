import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/library_backup_service.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';

void main() {
  test(
    'backup restores records and verified managed files atomically',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leeef-backup-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = LibraryRepository(
        database: database,
        deviceId: 'test-device',
        idGenerator: _IDs().next,
      );
      final source = File('${directory.path}/source.txt');
      await source.writeAsString('portable book');
      final bookId = await repository.createBookMetadata(
        sha256: List.filled(64, 'a').join(),
        title: 'Portable',
        mediaType: 'text/plain',
        filePath: source.path,
      );
      await repository.createBookmark(
        bookId: bookId,
        locator: 'offset:3',
        title: 'Remember',
      );

      final backup = File('${directory.path}/library.leeef-backup');
      final service = LibraryBackupService(database: database);
      final exported = await service.exportTo(backup);
      expect(exported.books, 1);
      expect(exported.files, 1);

      await repository.softDeleteBook(bookId);
      final restored = await service.restoreFrom(
        backup,
        Directory('${directory.path}/library'),
      );
      expect(restored.books, 1);
      final book = await repository.getBook(bookId);
      expect(book?.isDeleted, isFalse);
      expect(await File(book!.filePath!).readAsString(), 'portable book');
      expect(
        await repository.watchBookmarks(bookId: bookId).first,
        hasLength(1),
      );
      expect(await repository.pendingSyncOperations(), isNotEmpty);
    },
  );

  test('invalid backup leaves the current database untouched', () async {
    final directory = await Directory.systemTemp.createTemp(
      'leeef-backup-bad-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LibraryRepository(database: database, deviceId: 'test');
    await repository.createBookMetadata(
      sha256: List.filled(64, 'b').join(),
      title: 'Keep me',
      mediaType: 'text/plain',
    );
    final bad = File('${directory.path}/bad.zip')..writeAsStringSync('broken');
    await expectLater(
      LibraryBackupService(
        database: database,
      ).restoreFrom(bad, Directory('${directory.path}/library')),
      throwsA(anything),
    );
    expect(await repository.watchLibrary().first, hasLength(1));
  });
}

class _IDs {
  var _next = 0;
  String next() => 'id-${_next++}';
}
