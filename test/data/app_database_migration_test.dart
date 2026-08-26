import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'creates a consistent database snapshot in a custom directory',
    () async {
      final directory = await Directory.systemTemp.createTemp('leeef-db-copy-');
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      var databaseClosed = false;
      try {
        await database
            .into(database.books)
            .insert(
              BooksCompanion.insert(
                id: 'book',
                sha256: 'f' * 64,
                title: 'Copied book',
                mediaType: 'text/plain',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            );
        final snapshot = await database.copyToDirectory(directory);
        await database.close();
        databaseClosed = true;
        final copied = AppDatabase.forTesting(NativeDatabase(snapshot));
        try {
          expect(
            (await copied.select(copied.books).getSingle()).title,
            'Copied book',
          );
        } finally {
          await copied.close();
        }
      } finally {
        if (!databaseClosed) await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('schema v2 migrates ratings, tags, cover hash, and sessions', () async {
    final directory = await Directory.systemTemp.createTemp('leeef-migration-');
    final file = File('${directory.path}/legacy.sqlite');
    final legacy = sqlite.sqlite3.open(file.path);
    legacy
      ..execute('''
        CREATE TABLE books (
          id TEXT NOT NULL PRIMARY KEY,
          sha256 TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          author TEXT NULL,
          description TEXT NULL,
          media_type TEXT NOT NULL,
          file_path TEXT NULL,
          cover_path TEXT NULL,
          is_available_locally INTEGER NOT NULL DEFAULT 1,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute(
        '''INSERT INTO books
           (id, sha256, title, media_type, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)''',
        [
          'book-1',
          'a' * 64,
          'Legacy book',
          'application/epub+zip',
          '2026-01-01T00:00:00.000Z',
          '2026-01-01T00:00:00.000Z',
        ],
      )
      ..execute('PRAGMA user_version = 2')
      ..close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    try {
      final book = await database.select(database.books).getSingle();
      expect(book.title, 'Legacy book');
      expect(book.rating, isNull);
      expect(book.coverSha256, isNull);
      expect(book.md5, isNull);
      expect(await database.select(database.tags).get(), isEmpty);
      expect(await database.select(database.bookTagEntries).get(), isEmpty);
      expect(await database.select(database.readingSessions).get(), isEmpty);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
