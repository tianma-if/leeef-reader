import 'dart:io';

import 'package:archive/archive.dart';
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
        idGenerator: _Ids(['book-1', 'operation-1', 'operation-2']).next,
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

  test('extracts EPUB title, author, description, and cover', () async {
    final source = File('${temporaryDirectory.path}/fallback.epub');
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
          <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles>
          </container>'''),
      )
      ..addFile(
        ArchiveFile.string(
          'OPS/book.opf',
          '''<package xmlns="http://www.idpf.org/2007/opf"
              xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0">
            <metadata>
              <dc:title>Extracted Title</dc:title>
              <dc:creator>First Author</dc:creator>
              <dc:creator>Second Author</dc:creator>
              <dc:description>Book description</dc:description>
            </metadata>
            <manifest>
              <item id="cover" href="images/cover.png"
                media-type="image/png" properties="cover-image"/>
            </manifest>
          </package>''',
        ),
      )
      ..addFile(ArchiveFile.bytes('OPS/images/cover.png', [1, 2, 3, 4]));
    await source.writeAsBytes(ZipEncoder().encodeBytes(archive));

    final book = await importer.importFile(source);

    expect(book.title, 'Extracted Title');
    expect(book.author, 'First Author、Second Author');
    expect(book.description, 'Book description');
    expect(book.coverPath, endsWith('.cover.png'));
    expect(await File(book.coverPath!).readAsBytes(), [1, 2, 3, 4]);
  });

  test('rejects unsupported files without changing the database', () async {
    final source = File('${temporaryDirectory.path}/notes.docx');
    await source.writeAsString('docx');

    await expectLater(
      importer.importFile(source),
      throwsA(isA<UnsupportedBookFormat>()),
    );
    expect(await database.select(database.books).get(), isEmpty);
  });

  for (final format in const [
    (extension: 'pdf', mediaType: 'application/pdf'),
    (extension: 'txt', mediaType: 'text/plain'),
    (extension: 'mobi', mediaType: 'application/x-mobipocket-ebook'),
    (extension: 'azw3', mediaType: 'application/vnd.amazon.ebook'),
    (extension: 'fb2', mediaType: 'application/x-fictionbook+xml'),
  ]) {
    test(
      'imports ${format.extension.toUpperCase()} into managed storage',
      () async {
        final source = File(
          '${temporaryDirectory.path}/Required Format.${format.extension}',
        );
        await source.writeAsString('format-content-${format.extension}');

        final book = await importer.importFile(source);

        expect(book.title, 'Required Format');
        expect(book.mediaType, format.mediaType);
        expect(book.filePath, endsWith('.${format.extension}'));
        expect(
          await File(book.filePath!).readAsString(),
          'format-content-${format.extension}',
        );
      },
    );
  }

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

  test('replaces a managed file and can release only its local copy', () async {
    final original = File('${temporaryDirectory.path}/Original.epub');
    final replacement = File('${temporaryDirectory.path}/Replacement.pdf');
    await original.writeAsString('old-content');
    await replacement.writeAsString('new-content');
    final imported = await importer.importFile(original);
    final oldPath = imported.filePath!;

    final replaced = await importer.replaceFile(
      book: imported,
      source: replacement,
    );

    expect(replaced.id, imported.id);
    expect(replaced.mediaType, 'application/pdf');
    expect(replaced.filePath, endsWith('.pdf'));
    expect(await File(replaced.filePath!).readAsString(), 'new-content');
    expect(await File(oldPath).exists(), isFalse);

    await importer.releaseLocalCopy(replaced);
    final released = await database.select(database.books).getSingle();
    expect(released.isAvailableLocally, isFalse);
    expect(released.filePath, isNull);
    expect(await File(replaced.filePath!).exists(), isFalse);
  });

  test('refuses to release a file outside managed storage', () async {
    final source = File('${temporaryDirectory.path}/External.epub');
    await source.writeAsString('keep-me');
    final bookId =
        await LibraryRepository(
          database: database,
          deviceId: 'device-b',
          idGenerator: _Ids(['external-book', 'external-op']).next,
        ).createBookMetadata(
          sha256: 'a' * 64,
          title: 'External',
          mediaType: 'application/epub+zip',
          filePath: source.path,
        );
    final book = await database.select(database.books).getSingle();
    expect(book.id, bookId);

    await expectLater(
      importer.releaseLocalCopy(book),
      throwsA(isA<StateError>()),
    );
    expect(await source.exists(), isTrue);
    expect(
      (await database.select(database.books).getSingle()).filePath,
      source.path,
    );
  });
}

class _Ids {
  _Ids(this._values);

  final List<String> _values;
  int _index = 0;

  String next() => _values[_index++];
}
