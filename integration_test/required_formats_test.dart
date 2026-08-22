import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/features/reader/reader_screen.dart';
import 'package:leeef_reader/src/features/reader/pdf_reader_screen.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_screen.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'TXT reads, navigates, restores progress, bookmarks, and excerpts',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final source = File('${fixture.root.path}/Required TXT.txt');
      await source.writeAsString(
        '第一章 开始\n${'第一页需要可以稳定阅读和选中文本。' * 140}\n第二章 继续\n${'第二页继续阅读。' * 140}',
      );
      final book = await fixture.importer.importFile(source);

      await tester.pumpWidget(fixture.reader(book, enableTxtPageCurl: true));
      await _pumpUntilFound(tester, find.byKey(const Key('txt-reader-text')));
      expect(find.textContaining('1 / '), findsOneWidget);

      final readerBounds = tester.getRect(find.byType(TxtReaderScreen));
      final gesture = await tester.startGesture(
        Offset(readerBounds.right - 24, readerBounds.center.dy),
      );
      await gesture.moveBy(Offset(-readerBounds.width * 0.24, -80));
      await _pumpUntilFound(tester, find.byKey(const Key('txt-page-curl')));
      await gesture.moveBy(Offset(-readerBounds.width * 0.48, -60));
      await gesture.up();
      await _pumpUntilFound(tester, find.textContaining('2 / '));

      await tester.tap(find.byTooltip('添加书签'));
      await tester.pumpAndSettle();
      expect(
        await fixture.database.select(fixture.database.bookmarks).get(),
        hasLength(1),
      );

      final selectable = tester.widget<SelectableText>(
        find.byKey(const Key('txt-reader-text')),
      );
      selectable.onSelectionChanged!(
        const TextSelection(baseOffset: 0, extentOffset: 6),
        SelectionChangedCause.longPress,
      );
      await tester.pump();
      await tester.tap(find.text('摘录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        await fixture.database.select(fixture.database.excerpts).get(),
        hasLength(1),
      );
      final progress = await fixture.repository.getReadingProgress(book.id);
      expect(progress?.locator, startsWith('txt:'));
      expect(progress?.page, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(fixture.reader(book, enableTxtPageCurl: true));
      await _pumpUntilFound(tester, find.byKey(const Key('txt-reader-text')));
      expect(find.textContaining('2 / '), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'PDF renders, navigates, restores progress, bookmarks, and excerpts',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final source = File('${fixture.root.path}/Required PDF.pdf');
      await source.writeAsBytes(_minimalPdf());
      final book = await fixture.importer.importFile(source);

      await tester.pumpWidget(fixture.reader(book));
      await _pumpUntilFound(tester, find.byKey(const Key('pdf-reader-view')));
      await _pumpUntilFound(
        tester,
        find.text('1 / 2'),
        timeout: const Duration(seconds: 20),
      );

      final pdfBounds = tester.getRect(find.byType(PdfReaderScreen));
      final pdfGesture = await tester.startGesture(
        Offset(pdfBounds.right - 24, pdfBounds.center.dy),
      );
      await pdfGesture.moveBy(Offset(-pdfBounds.width * 0.24, -60));
      await _pumpUntilFound(tester, find.byKey(const Key('pdf-page-curl')));
      await pdfGesture.moveBy(Offset(-pdfBounds.width * 0.48, -50));
      await pdfGesture.up();
      await _pumpUntilFound(tester, find.text('2 / 2'));
      await tester.pump(const Duration(milliseconds: 700));

      await tester.tap(find.byTooltip('添加书签'));
      await tester.pumpAndSettle();
      expect(
        await fixture.database.select(fixture.database.bookmarks).get(),
        hasLength(1),
      );

      final viewer = tester.widget<PdfViewer>(
        find.byKey(const Key('pdf-reader-view')),
      );
      await viewer.controller!.textSelectionDelegate.selectAllText();
      await _pumpUntilFound(
        tester,
        find.text('摘录'),
        timeout: const Duration(seconds: 20),
      );
      await tester.tap(find.text('摘录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(
        await fixture.database.select(fixture.database.excerpts).get(),
        hasLength(1),
      );
      final progress = await fixture.repository.getReadingProgress(book.id);
      expect(progress?.locator, 'pdf:2');
      expect(progress?.page, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(fixture.reader(book));
      await _pumpUntilFound(
        tester,
        find.text('2 / 2'),
        timeout: const Duration(seconds: 20),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    },
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

class _Fixture {
  _Fixture({
    required this.root,
    required this.database,
    required this.repository,
    required this.importer,
  });

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'leeef-required-format-',
    );
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var id = 0;
    final repository = LibraryRepository(
      database: database,
      deviceId: 'integration-device',
      idGenerator: () => 'integration-${id++}',
    );
    return _Fixture(
      root: root,
      database: database,
      repository: repository,
      importer: BookImportService(
        repository: repository,
        libraryDirectory: Directory('${root.path}/library'),
      ),
    );
  }

  final Directory root;
  final AppDatabase database;
  final LibraryRepository repository;
  final BookImportService importer;

  Widget reader(BookRecord book, {bool enableTxtPageCurl = false}) =>
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          home: enableTxtPageCurl
              ? TxtReaderScreen(book: book, pageCurlEnabled: true)
              : ReaderScreen(book: book),
        ),
      );

  Future<void> dispose() async {
    await database.close();
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await root.delete(recursive: true);
        return;
      } on PathAccessException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }
}

List<int> _minimalPdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>',
    _pdfStream('BT /F1 18 Tf 40 330 Td (PDF page one selectable text) Tj ET'),
    _pdfStream('BT /F1 18 Tf 40 330 Td (PDF page two selectable text) Tj ET'),
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  var byteLength = latin1.encode(buffer.toString()).length;
  for (var index = 0; index < objects.length; index++) {
    offsets.add(byteLength);
    final object = '${index + 1} 0 obj\n${objects[index]}\nendobj\n';
    buffer.write(object);
    byteLength += latin1.encode(object).length;
  }
  final xref = byteLength;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(buffer.toString());
}

String _pdfStream(String content) =>
    '<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream';
