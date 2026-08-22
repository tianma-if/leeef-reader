import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/page_curl/foliate_page_snapshot_view.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
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

    await engine.setLayout(maxColumnCount: 1, margin: 32);
    final layout = await engine.probeLayout();
    expect(layout.flow, 'paginated');
    expect(layout.maxColumnCount, 1);
    expect(layout.margin, '32px');
    expect(layout.renderedSections, greaterThan(0));
    expect(layout.textLength, greaterThan(0));

    await engine.goTo(info.toc.single.href);
    await engine.next();
    final location = await relocation.timeout(const Duration(seconds: 10));
    expect(location.cfi, startsWith('epubcfi('));

    final selection = await engine.probeTextSelection();
    expect(selection.quote, isNotEmpty);
    expect(selection.cfi, startsWith('epubcfi('));
  });

  testWidgets('page curl shader renders and completes an interactive drag', (
    tester,
  ) async {
    final currentPage = await _solidImage(const ui.Color(0xFFF7F1E3));
    final nextPage = await _solidImage(const ui.Color(0xFFCEE5D0));
    addTearDown(() {
      currentPage.dispose();
      nextPage.dispose();
    });
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PageCurlSurface(
              currentPage: currentPage,
              nextPage: nextPage,
              onTurnCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageCurlSurface), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });

  testWidgets(
    'mid-turn page curl has an oblique fold instead of a flat strip',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final currentPage = await _solidImage(const ui.Color(0xFFF7F1E3));
      final nextPage = await _solidImage(const ui.Color(0xFFCEE5D0));
      addTearDown(() {
        currentPage.dispose();
        nextPage.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('curl-frame'),
              child: PageCurlSurface(
                currentPage: currentPage,
                nextPage: nextPage,
                onTurnCompleted: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(390, 540));
      await gesture.moveBy(const Offset(-200, -90));
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('curl-frame')),
      );
      final frame = await boundary.toImage();
      addTearDown(frame.dispose);
      final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      final upper = _pixelAt(pixels!, frame.width, 300, 120);
      final lower = _pixelAt(pixels, frame.width, 300, 510);

      expect(upper.r, greaterThan(upper.g), reason: 'upper area stays current');
      expect(lower.g, greaterThan(lower.r), reason: 'lower corner is revealed');
      expect(upper, isNot(lower));

      await gesture.cancel();
    },
  );

  testWidgets('page curl can automatically complete after a single tap', (
    tester,
  ) async {
    final currentPage = await _solidImage(const ui.Color(0xFFF7F1E3));
    final nextPage = await _solidImage(const ui.Color(0xFFCEE5D0));
    addTearDown(() {
      currentPage.dispose();
      nextPage.dispose();
    });
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: PageCurlSurface(
              currentPage: currentPage,
              nextPage: nextPage,
              autoComplete: true,
              onTurnCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(completed, isTrue);
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
    await tester.pump(const Duration(seconds: 1));
    final images = await imagesFuture;

    expect(images, hasLength(2));
    expect(
      images.every((image) => image.width > 0 && image.height > 0),
      isTrue,
    );
  });
}

Future<ui.Image> _solidImage(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(64, 64);
  } finally {
    picture.dispose();
  }
}

({int r, int g, int b, int a}) _pixelAt(
  ByteData pixels,
  int width,
  int x,
  int y,
) {
  final offset = (y * width + x) * 4;
  return (
    r: pixels.getUint8(offset),
    g: pixels.getUint8(offset + 1),
    b: pixels.getUint8(offset + 2),
    a: pixels.getUint8(offset + 3),
  );
}
