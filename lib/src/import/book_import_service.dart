import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/import/epub_metadata_extractor.dart';

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

    final digests = await _digests(source);
    final hash = digests.sha256;
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

    EpubMetadata? metadata;
    if (format.extension == 'epub') {
      metadata = await const EpubMetadataExtractor().extract(destination);
    }
    String? coverPath;
    String? coverSha256;
    if (metadata?.coverBytes case final bytes?) {
      final extension = metadata?.coverExtension ?? 'img';
      final cover = File('${_libraryDirectory.path}/$hash.cover.$extension');
      await cover.writeAsBytes(bytes, flush: true);
      coverPath = cover.path;
      coverSha256 = sha256.convert(bytes).toString();
    }

    final bookId = await _repository.createBookMetadata(
      sha256: hash,
      md5: digests.md5,
      title: metadata?.title ?? _displayName(source.path),
      author: metadata?.author,
      description: metadata?.description,
      mediaType: format.mediaType,
      filePath: destination.path,
      coverPath: coverPath,
      coverSha256: coverSha256,
    );
    final book = await _repository.getBook(bookId);
    if (book == null) throw StateError('Imported book was not persisted.');
    return book;
  }

  Future<BookRecord> replaceFile({
    required BookRecord book,
    required File source,
  }) async {
    if (!await source.exists()) {
      throw ArgumentError.value(source.path, 'source', 'File does not exist.');
    }
    final format = _formatFor(source.path);
    await _libraryDirectory.create(recursive: true);
    final digests = await _digests(source);
    final hash = digests.sha256;
    final destination = File(
      '${_libraryDirectory.path}/$hash.${format.extension}',
    );
    if (!await destination.exists() || await _digest(destination) != hash) {
      final staging = File(
        '${destination.path}.replacing-$pid-${DateTime.now().microsecondsSinceEpoch}',
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
    final previousPath = book.filePath;
    await _repository.replaceBookFile(
      bookId: book.id,
      sha256: hash,
      md5: digests.md5,
      mediaType: format.mediaType,
      filePath: destination.path,
    );
    if (previousPath != null && previousPath != destination.path) {
      await _deleteManagedFile(previousPath);
    }
    return (await _repository.getBook(book.id))!;
  }

  Future<void> releaseLocalCopy(BookRecord book) async {
    final filePath = book.filePath;
    if (filePath != null) await _deleteManagedFile(filePath);
    await _repository.detachLocalBookFile(book.id);
  }

  Future<void> _deleteManagedFile(String filePath) async {
    final libraryPath = _libraryDirectory.absolute.path;
    final target = File(filePath).absolute;
    if (!target.path.startsWith('$libraryPath${Platform.pathSeparator}')) {
      throw StateError('Refusing to delete a file outside managed storage.');
    }
    if (await target.exists()) await target.delete();
  }

  static _BookFormat _formatFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.epub')) {
      return const _BookFormat('epub', 'application/epub+zip');
    }
    if (lower.endsWith('.pdf')) {
      return const _BookFormat('pdf', 'application/pdf');
    }
    if (lower.endsWith('.txt')) {
      return const _BookFormat('txt', 'text/plain');
    }
    if (lower.endsWith('.mobi')) {
      return const _BookFormat('mobi', 'application/x-mobipocket-ebook');
    }
    if (lower.endsWith('.azw3')) {
      return const _BookFormat('azw3', 'application/vnd.amazon.ebook');
    }
    if (lower.endsWith('.fb2')) {
      return const _BookFormat('fb2', 'application/x-fictionbook+xml');
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

  static Future<({String sha256, String md5})> _digests(File file) async {
    final bytes = await file.readAsBytes();
    return (
      sha256: sha256.convert(bytes).toString(),
      md5: md5.convert(bytes).toString(),
    );
  }
}

class _BookFormat {
  const _BookFormat(this.extension, this.mediaType);

  final String extension;
  final String mediaType;
}
