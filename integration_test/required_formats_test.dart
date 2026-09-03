import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/features/reader/reader_screen.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_screen.dart';
import 'package:leeef_reader/src/import/book_import_service.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    await Future.wait([
      preferences.setString('leeef.reader.flow', 'paginated'),
      preferences.setString('leeef.reader.page_turn_effect', 'curl'),
      preferences.setBool('leeef.reader.show_header', true),
      preferences.setBool('leeef.reader.show_footer', true),
      preferences.setString('leeef.reader.footer_content', 'page'),
    ]);
  });

  testWidgets('desktop EPUB turns pages by clicking a slide zone', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final fixtureData = await rootBundle.load('assets/fixtures/m0.epub');
    final source = File('${fixture.root.path}/Required EPUB.epub');
    await source.writeAsBytes(
      fixtureData.buffer.asUint8List(
        fixtureData.offsetInBytes,
        fixtureData.lengthInBytes,
      ),
    );
    final book = await fixture.importer.importFile(source);

    await tester.pumpWidget(fixture.reader(book));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('epub-tap-right-zone')),
      timeout: const Duration(seconds: 20),
    );
    await tester.pump(const Duration(milliseconds: 800));
    final initialProgress = await fixture.repository.getReadingProgress(
      book.id,
    );
    await tester.tap(find.byKey(const Key('epub-tap-right-zone')));
    expect(find.byKey(const Key('epub-page-curl')), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));

    final completedProgress = await fixture.repository.getReadingProgress(
      book.id,
    );
    expect(completedProgress?.locator, startsWith('epubcfi('));
    expect(completedProgress?.locator, isNot(initialProgress?.locator));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

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
      expect(find.byKey(const ValueKey('txt-page-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('txt-tap-right-zone')));
      expect(find.byKey(const Key('txt-page-curl')), findsNothing);
      expect(find.byKey(const Key('txt-page-slide')), findsOneWidget);
      await _pumpUntilFound(tester, find.byKey(const ValueKey('txt-page-1')));

      await _showControlsIfHidden(tester, '添加书签');
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
      await _pumpUntil(
        tester,
        () async =>
            (await fixture.repository.getReadingProgress(
              book.id,
            ))?.locator.startsWith('txt:') ??
            false,
      );
      final progress = await fixture.repository.getReadingProgress(book.id);
      expect(progress?.locator, startsWith('txt:'));
      expect(progress?.page, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(fixture.reader(book, enableTxtPageCurl: true));
      await _pumpUntilFound(tester, find.byKey(const Key('txt-reader-text')));
      expect(find.byKey(const ValueKey('txt-page-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('TXT visible pages are contiguous across repeated desktop taps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final sourceText = List.generate(
      12000,
      (index) => String.fromCharCode(0x4E00 + index),
    ).join();
    final source = File('${fixture.root.path}/Continuous TXT.txt');
    await source.writeAsString(sourceText);
    final book = await fixture.importer.importFile(source);

    await tester.pumpWidget(fixture.reader(book, enableTxtPageCurl: true));
    await _pumpUntilFound(tester, find.byKey(const Key('txt-reader-text')));

    var sourceOffset = 0;
    for (var pageIndex = 0; pageIndex < 5; pageIndex++) {
      final pageFinder = find.byKey(ValueKey('txt-page-$pageIndex'));
      await _pumpUntilFound(tester, pageFinder);
      final selectable = tester.widget<SelectableText>(
        find.byKey(const Key('txt-reader-text')),
      );
      final visibleText = selectable.textSpan!.toPlainText();
      expect(visibleText, isNotEmpty);
      expect(sourceText.substring(sourceOffset), startsWith(visibleText));

      final pageRect = tester.getRect(pageFinder);
      final textRect = tester.getRect(find.byKey(const Key('txt-reader-text')));
      expect(textRect.top, closeTo(pageRect.top + 24, 1));
      expect(textRect.width, closeTo(pageRect.width - 48, 1));
      expect(textRect.bottom, lessThanOrEqualTo(pageRect.bottom - 71));
      final measured = TextPainter(
        text: TextSpan(text: visibleText, style: selectable.style),
        textDirection: TextDirection.ltr,
        strutStyle: StrutStyle.fromTextStyle(selectable.style!),
      )..layout(maxWidth: textRect.width - 3);
      expect(measured.height, closeTo(textRect.height, 1));
      measured.dispose();
      expect(textRect.bottom, greaterThan(pageRect.bottom - 110));
      sourceOffset += visibleText.length;

      if (pageIndex < 4) {
        await tester.tap(find.byKey(const Key('txt-tap-right-zone')));
        await tester.pump(const Duration(milliseconds: 800));
      }
    }

    await tester.tap(find.byKey(const Key('txt-tap-left-zone')));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const ValueKey('txt-page-3')), findsOneWidget);
    var anchor = tester
        .widget<SelectableText>(find.byKey(const Key('txt-reader-text')))
        .textSpan!
        .toPlainText()
        .characters
        .first;
    for (final size in [const Size(1920, 960), const Size(700, 800)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final text = tester
          .widget<SelectableText>(find.byKey(const Key('txt-reader-text')))
          .textSpan!
          .toPlainText();
      expect(text, contains(anchor));
      final rect = tester.getRect(find.byKey(const Key('txt-reader-text')));
      expect(rect.width, closeTo(size.width - 48, 1));
      expect(rect.top, 80);
      anchor = text.characters.first;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('TXT visible pages are contiguous through mobile page curl', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final sourceText = List.generate(
      2400,
      (index) => '第${index.toString().padLeft(4, '0')}段内容连续验证。',
    ).join();
    final source = File('${fixture.root.path}/Mobile Continuous TXT.txt');
    await source.writeAsString(sourceText);
    final book = await fixture.importer.importFile(source);

    await tester.pumpWidget(fixture.reader(book, enableTxtPageCurl: true));
    await _pumpUntilFound(tester, find.byKey(const Key('txt-reader-text')));
    expect(find.byKey(const Key('txt-curl-right-zone')), findsOneWidget);
    expect(find.byKey(const Key('txt-page-slide')), findsNothing);

    var sourceOffset = 0;
    for (var pageIndex = 0; pageIndex < 5; pageIndex++) {
      final pageFinder = find.byKey(ValueKey('txt-page-$pageIndex'));
      await _pumpUntilFound(
        tester,
        pageFinder,
        timeout: const Duration(seconds: 20),
      );
      final selectable = tester.widget<SelectableText>(
        find.byKey(const Key('txt-reader-text')),
      );
      final visibleText = selectable.textSpan!.toPlainText();
      expect(visibleText, isNotEmpty);
      expect(
        sourceText.substring(sourceOffset, sourceOffset + visibleText.length),
        visibleText,
      );

      final pageRect = tester.getRect(pageFinder);
      final textRect = tester.getRect(find.byKey(const Key('txt-reader-text')));
      expect(textRect.top, closeTo(pageRect.top + 24, 1));
      expect(textRect.bottom, lessThanOrEqualTo(pageRect.bottom - 71));
      sourceOffset += visibleText.length;

      if (pageIndex < 4) {
        await tester.tap(find.byKey(const Key('txt-curl-right-zone')));
        await _pumpUntilFound(
          tester,
          find.byKey(ValueKey('txt-page-${pageIndex + 1}')),
          timeout: const Duration(seconds: 20),
        );
        await _pumpUntilNotFound(
          tester,
          find.byKey(const Key('txt-page-curl')),
          timeout: const Duration(seconds: 20),
        );
      }
    }

    await tester.tap(find.byKey(const Key('txt-curl-left-zone')));
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('txt-page-3')),
      timeout: const Duration(seconds: 20),
    );
    await _pumpUntilNotFound(
      tester,
      find.byKey(const Key('txt-page-curl')),
      timeout: const Duration(seconds: 20),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, skip: !(Platform.isAndroid || Platform.isIOS));

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

      await tester.tap(find.byKey(const Key('pdf-tap-right-zone')));
      expect(find.byKey(const Key('pdf-page-curl')), findsNothing);
      await _pumpUntilFound(tester, find.text('2 / 2'));
      await tester.pump(const Duration(milliseconds: 700));

      await _showControlsIfHidden(tester, '添加书签');
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

Future<void> _pumpUntilNotFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsNothing);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Condition was not met within $timeout.');
}

Future<void> _showControlsIfHidden(WidgetTester tester, String tooltip) async {
  if (find.byTooltip(tooltip).evaluate().isNotEmpty) return;
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byTooltip(tooltip), findsOneWidget);
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
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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
