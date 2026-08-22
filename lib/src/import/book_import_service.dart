import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';

class UnsupportedBookFormat implements Exception {
  const UnsupportedBookFormat(this.path);

  final String path;

  @override
  String toString() => 'Unsupported book format: $path';
}

class BookImportService {
  BookImportService({
    required LibraryRepository repository,
    required Directory libraryDirectory,
  }) : _repository = repository,
       _libraryDirectory = libraryDirectory;

  final LibraryRepository _repository;
  final Directory _libraryDirectory;

  Future<BookRecord> importFile(File source) async {
    if (!await source.exists()) {
      throw ArgumentError.value(source.path, 'source', 'File does not exist.');
    }
    final format = _formatFor(source.path);
    await _libraryDirectory.create(recursive: true);

    final hash = await _digest(source);
    final destination = File(
      '${_libraryDirectory.path}/$hash.${format.extension}',
    );
    final existingIsValid =
        await destination.exists() && await _digest(destination) == hash;
    if (!existingIsValid) {
      final staging = File(
        '${destination.path}.importing-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await source.openRead().pipe(staging.openWrite());
        if (await destination.exists()) await destination.delete();
        await staging.rename(destination.path);
      } on Object {
        if (await staging.exists()) await staging.delete();
        rethrow;
      }
    }

    final bookId = await _repository.createBookMetadata(
      sha256: hash,
      title: _displayName(source.path),
      mediaType: format.mediaType,
      filePath: destination.path,
    );
    final book = await _repository.getBook(bookId);
    if (book == null) throw StateError('Imported book was not persisted.');
    return book;
  }

  static _BookFormat _formatFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.epub')) {
      return const _BookFormat('epub', 'application/epub+zip');
    }
    throw UnsupportedBookFormat(path);
  }

  static String _displayName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final filename = normalized.substring(normalized.lastIndexOf('/') + 1);
    final extension = filename.lastIndexOf('.');
    return extension > 0 ? filename.substring(0, extension) : filename;
  }

  static Future<String> _digest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}

class _BookFormat {
  const _BookFormat(this.extension, this.mediaType);

  final String extension;
  final String mediaType;
}
