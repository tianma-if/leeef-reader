import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/page_curl/foliate_page_snapshot_view.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';
import 'package:leeef_reader/src/reader/foliate_reader_view.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('foliate loads EPUB, navigates with CFI, and selects text', (
    tester,
  ) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'leeef-foliate-integration-',
    );
    final engine = FoliateReaderEngine();
    addTearDown(() async {
      await engine.close();
      await temporaryDirectory.delete(recursive: true);
    });

    final fixtureData = await rootBundle.load('assets/fixtures/m0.epub');
    final fixture = File('${temporaryDirectory.path}/m0.epub');
    await fixture.writeAsBytes(
      fixtureData.buffer.asUint8List(
        fixtureData.offsetInBytes,
        fixtureData.lengthInBytes,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FoliateReaderView(engine: engine)),
      ),
    );
    await tester.pumpAndSettle();

    final relocation = engine.events
        .where((event) => event is ReaderRelocated)
        .cast<ReaderRelocated>()
        .first;
    final info = await engine.open(
      ReaderBookSource(
        bookId: 'm0-fixture',
        file: fixture,
        mediaType: 'application/epub+zip',
      ),
    );

    expect(info.title, 'Leeef M0 验证书');
    expect(info.author, 'Leeef Team');
    expect(info.toc.single.label, '第一章');

    await engine.setLayout(
      maxColumnCount: 1,
      margin: 32,
      pageTurnEffect: 'slide',
    );
    final layout = await engine.probeLayout();
    expect(layout.flow, 'paginated');
    expect(layout.maxColumnCount, 1);
    expect(layout.margin, '32px');
    expect(layout.animated, isTrue);
    expect(layout.renderedSections, greaterThan(0));
    expect(layout.textLength, greaterThan(0));
    expect(await engine.bookText(), contains('验证'));

    await engine.setLayout(pageTurnEffect: 'none');
    expect((await engine.probeLayout()).animated, isFalse);

    await engine.setTheme(
      foreground: '#112233',
      background: '#f0eadc',
      fontSize: 21,
      lineHeight: 1.9,
      fontFamily: 'serif',
      fontWeight: 500,
      letterSpacing: 0.5,
      paragraphSpacing: 0.8,
      textAlign: 'justify',
    );
    final results = await engine.search('验证');
    expect(results, isNotEmpty);
    expect(results.first.cfi, startsWith('epubcfi('));
    await engine.goTo(results.first.cfi);
    await engine.clearSearch();

    await engine.goTo(info.toc.single.href);
    await engine.next();
    final location = await relocation.timeout(const Duration(seconds: 10));
    expect(location.cfi, startsWith('epubcfi('));

    final selection = await engine.probeTextSelection();
    expect(selection.quote, isNotEmpty);
    expect(selection.cfi, startsWith('epubcfi('));
  });

  testWidgets('foliate replica pre-renders adjacent page textures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'leeef-snapshot-integration-',
    );
    final fixtureData = await rootBundle.load('assets/fixtures/m0.epub');
    final fixture = File('${temporaryDirectory.path}/m0.epub');
    await fixture.writeAsBytes(
      fixtureData.buffer.asUint8List(
        fixtureData.offsetInBytes,
        fixtureData.lengthInBytes,
      ),
    );
    final source = ReaderBookSource(
      bookId: 'm0-snapshot-fixture',
      file: fixture,
      mediaType: 'application/epub+zip',
    );
    final controller = FoliatePageSnapshotController();
    final cache = PageSnapshotCache(source: controller);
    addTearDown(() async {
      cache.clear();
      await temporaryDirectory.delete(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: FoliatePageSnapshotView(
                controller: controller,
                book: source,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(FoliatePageSnapshotView)),
      const Size(320, 480),
    );

    const common = (
      bookId: 'm0-snapshot-fixture',
      viewportWidth: 320,
      viewportHeight: 480,
      themeRevision: 0,
    );
    final imagesFuture = Future.wait([
      cache.get(
        PageSnapshotKey(
          bookId: common.bookId,
          locator: 'chapter.xhtml',
          viewportWidth: common.viewportWidth,
          viewportHeight: common.viewportHeight,
          themeRevision: common.themeRevision,
          slot: PageSnapshotSlot.current,
        ),
      ),
      cache.get(
        PageSnapshotKey(
          bookId: common.bookId,
          locator: 'epubcfi(/6/2!/4/6/2:0)',
          viewportWidth: common.viewportWidth,
          viewportHeight: common.viewportHeight,
          themeRevision: common.themeRevision,
          slot: PageSnapshotSlot.next,
        ),
      ),
    ]);
    final images = await _pumpUntilComplete(tester, imagesFuture);

    expect(images, hasLength(2));
    expect(
      images.every((image) => image.width > 0 && image.height > 0),
      isTrue,
    );
    final pixels = await images.first.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);
    var darkSamples = 0;
    for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4 * 97) {
      if (pixels.getUint8(offset) < 180 &&
          pixels.getUint8(offset + 1) < 180 &&
          pixels.getUint8(offset + 2) < 180) {
        darkSamples++;
      }
    }
    expect(darkSamples, greaterThan(8), reason: 'snapshot contains EPUB text');
    for (final image in images) {
      image.dispose();
    }
  });
}

Future<T> _pumpUntilComplete<T>(
  WidgetTester tester,
  Future<T> future, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  T? value;
  Object? error;
  StackTrace? stackTrace;
  var completed = false;
  future.then(
    (result) {
      value = result;
      completed = true;
    },
    onError: (Object caughtError, StackTrace caughtStackTrace) {
      error = caughtError;
      stackTrace = caughtStackTrace;
      completed = true;
    },
  );
  final deadline = DateTime.now().add(timeout);
  while (!completed && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!completed) throw TimeoutException('Future did not complete in $timeout');
  if (error != null) Error.throwWithStackTrace(error!, stackTrace!);
  return value as T;
}
