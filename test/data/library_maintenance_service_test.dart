import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/library_maintenance_service.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';

void main() {
  test(
    'inspects storage, backfills MD5, repairs missing paths, and clears orphans',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'leeef-maintenance-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final ids = _Ids();
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device',
        idGenerator: ids.next,
      );
      final local = File('${directory.path}/book.txt')
        ..writeAsStringSync('hello');
      final orphan = File('${directory.path}/orphan.cache')
        ..writeAsStringSync('unused');
      final databaseFile = File('${directory.path}/leeef.sqlite')
        ..writeAsStringSync('database');
      final localID = await repository.createBookMetadata(
        sha256: 'a' * 64,
        title: 'Local',
        mediaType: 'text/plain',
        filePath: local.path,
      );
      await repository.createBookMetadata(
        sha256: 'b' * 64,
        title: 'Missing',
        mediaType: 'text/plain',
        filePath: '${directory.path}/gone.txt',
      );
      final service = LibraryMaintenanceService(
        repository: repository,
        libraryDirectory: directory,
      );

      final before = await service.inspect();
      expect(before.localBooks, 1);
      expect(before.missingBooks, hasLength(1));
      expect(before.orphanBytes, await orphan.length());
      expect(await service.backfillMd5(), 1);
      expect(
        (await repository.getBook(localID))!.md5,
        '5d41402abc4b2a76b9719d911017c592',
      );
      expect(await service.repairMissingFileFlags(), 1);
      expect(await service.clearOrphanFiles(), greaterThan(0));
      expect(await orphan.exists(), isFalse);
      expect(await databaseFile.exists(), isTrue);
    },
  );

  test(
    'migrates local files and atomically updates repository paths',
    () async {
      final source = await Directory.systemTemp.createTemp('leeef-source-');
      final target = await Directory.systemTemp.createTemp('leeef-target-');
      addTearDown(() async {
        if (await source.exists()) await source.delete(recursive: true);
        if (await target.exists()) await target.delete(recursive: true);
      });
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = LibraryRepository(
        database: database,
        deviceId: 'device',
        idGenerator: _Ids().next,
      );
      final original = File('${source.path}/novel.epub')
        ..writeAsStringSync('epub payload');
      final id = await repository.createBookMetadata(
        sha256: 'c' * 64,
        title: 'Novel',
        mediaType: 'application/epub+zip',
        filePath: original.path,
      );

      final count = await LibraryMaintenanceService(
        repository: repository,
        libraryDirectory: source,
      ).migrateFilesTo(target);

      final migrated = await repository.getBook(id);
      expect(count, 1);
      expect(migrated!.filePath, '${target.path}/${'c' * 64}.epub');
      expect(await File(migrated.filePath!).readAsString(), 'epub payload');
      expect(await original.exists(), isFalse);
    },
  );
}

class _Ids {
  var value = 0;
  String next() => 'id-${value++}';
}
