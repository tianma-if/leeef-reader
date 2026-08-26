import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';

class BackupReport {
  const BackupReport({
    required this.books,
    required this.files,
    required this.bytes,
  });
  final int books;
  final int files;
  final int bytes;
}

/// Portable, integrity-checked backup of all Leeef records and managed files.
/// Restore validates and extracts into a fresh directory before atomically
/// replacing database rows, so a malformed backup cannot partially apply.
class LibraryBackupService {
  LibraryBackupService({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  static const format = 'leeef-backup';
  static const version = 1;
  static const _tables = <String>[
    'books',
    'tags',
    'book_tag_entries',
    'bookshelves',
    'bookshelf_entries',
    'excerpts',
    'bookmarks',
    'reading_progresses',
    'reading_progress_history',
    'reading_sessions',
    'sync_operations',
    'audit_events',
  ];
  static const _deleteOrder = <String>[
    'book_tag_entries',
    'bookshelf_entries',
    'reading_progress_history',
    'reading_progresses',
    'reading_sessions',
    'excerpts',
    'bookmarks',
    'tags',
    'bookshelves',
    'books',
    'sync_operations',
    'audit_events',
  ];

  Future<BackupReport> exportTo(File destination) async {
    final archive = Archive();
    final tableRows = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      tableRows[table] =
          (await _database.customSelect('SELECT * FROM $table').get())
              .map((row) => Map<String, Object?>.from(row.data))
              .toList();
    }

    final entries = <String, String>{};
    var fileCount = 0;
    for (final row in tableRows['books']!) {
      for (final column in const ['file_path', 'cover_path']) {
        final sourcePath = row[column] as String?;
        if (sourcePath == null || sourcePath.isEmpty) continue;
        final source = File(sourcePath);
        if (!await source.exists()) {
          row[column] = null;
          if (column == 'file_path') row['is_available_locally'] = 0;
          continue;
        }
        final bytes = await source.readAsBytes();
        final digest = sha256.convert(bytes).toString();
        final extension = column == 'file_path'
            ? _extension(source.path)
            : _extension(source.path, fallback: '.cover');
        final entryName = 'files/$digest$extension';
        if (!entries.containsKey(entryName)) {
          archive.addFile(ArchiveFile.bytes(entryName, bytes));
          entries[entryName] = digest;
          fileCount++;
        }
        row[column] = entryName;
      }
    }

    final manifest = <String, Object?>{
      'format': format,
      'version': version,
      'databaseSchemaVersion': _database.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tableRows,
      'files': entries,
    };
    archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    final encoded = ZipEncoder().encodeBytes(archive);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(encoded, flush: true);
    return BackupReport(
      books: tableRows['books']!.length,
      files: fileCount,
      bytes: encoded.length,
    );
  }

  Future<BackupReport> restoreFrom(
    File source,
    Directory libraryDirectory,
  ) async {
    final archive = ZipDecoder().decodeBytes(
      await source.readAsBytes(),
      verify: true,
    );
    final byName = <String, ArchiveFile>{
      for (final file in archive.files) file.name: file,
    };
    final manifestFile = byName['manifest.json'];
    if (manifestFile == null || !manifestFile.isFile) {
      throw const FormatException('Backup has no manifest.json.');
    }
    final decoded = jsonDecode(utf8.decode(manifestFile.readBytes()!));
    if (decoded is! Map ||
        decoded['format'] != format ||
        decoded['version'] != version) {
      throw const FormatException('Unsupported Leeef backup format.');
    }
    final rawTables = decoded['tables'];
    final rawFiles = decoded['files'];
    if (rawTables is! Map || rawFiles is! Map) {
      throw const FormatException('Backup manifest is incomplete.');
    }
    for (final table in _tables) {
      if (rawTables[table] is! List) {
        throw FormatException('Backup table $table is missing.');
      }
    }

    final restoreDirectory = Directory(
      '${libraryDirectory.path}/restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    await restoreDirectory.create(recursive: true);
    var restoredFiles = 0;
    try {
      for (final item in rawFiles.entries) {
        final name = item.key as String;
        final expectedHash = item.value as String;
        if (!name.startsWith('files/') || name.contains('..')) {
          throw const FormatException('Unsafe file path in backup.');
        }
        final archiveFile = byName[name];
        if (archiveFile == null || !archiveFile.isFile) {
          throw FormatException('Backup file $name is missing.');
        }
        final bytes = archiveFile.readBytes()!;
        if (sha256.convert(bytes).toString() != expectedHash) {
          throw FormatException(
            'Backup file $name failed integrity validation.',
          );
        }
        await File(
          '${restoreDirectory.path}/${name.substring(6)}',
        ).writeAsBytes(bytes, flush: true);
        restoredFiles++;
      }

      final rows = <String, List<Map<String, Object?>>>{};
      for (final table in _tables) {
        rows[table] = (rawTables[table] as List)
            .map((item) => Map<String, Object?>.from(item as Map))
            .toList();
      }
      for (final book in rows['books']!) {
        for (final column in const ['file_path', 'cover_path']) {
          final entry = book[column] as String?;
          if (entry != null) {
            book[column] = '${restoreDirectory.path}/${entry.substring(6)}';
          }
        }
      }

      await _database.transaction(() async {
        for (final table in _deleteOrder) {
          await _database.customStatement('DELETE FROM $table');
        }
        for (final table in _tables) {
          for (final row in rows[table]!) {
            if (row.isEmpty) continue;
            final columns = row.keys.toList(growable: false);
            final placeholders = List.filled(columns.length, '?').join(',');
            await _database.customStatement(
              'INSERT INTO $table (${columns.join(',')}) VALUES ($placeholders)',
              columns.map((column) => row[column]).toList(growable: false),
            );
          }
        }
        // Re-publish restored operation records; operation IDs make this safe.
        await _database.customStatement(
          'UPDATE sync_operations SET applied_at = NULL',
        );
      });
      return BackupReport(
        books: rows['books']!.length,
        files: restoredFiles,
        bytes: await source.length(),
      );
    } on Object {
      if (await restoreDirectory.exists()) {
        await restoreDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  static String _extension(String path, {String fallback = '.bin'}) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash || dot == path.length - 1) return fallback;
    final extension = path.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : fallback;
  }
}
