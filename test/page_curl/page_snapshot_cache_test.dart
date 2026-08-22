import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';

void main() {
  test('deduplicates in-flight and cached snapshot requests', () async {
    final source = _FakeSnapshotSource();
    final cache = PageSnapshotCache(source: source);
    final key = _key('one');

    final images = await Future.wait([cache.get(key), cache.get(key)]);
    final cached = await cache.get(key);

    expect(source.captureCount, 1);
    expect(images[0], isNot(same(images[1])));
    expect(cached, isNot(same(images[0])));
    for (final image in [...images, cached]) {
      image.dispose();
    }
    cache.clear();
  });

  test('evicts least recently used snapshot at capacity', () async {
    final source = _FakeSnapshotSource();
    final cache = PageSnapshotCache(source: source, capacity: 2);

    for (final locator in ['one', 'two', 'three', 'one']) {
      (await cache.get(_key(locator))).dispose();
    }

    expect(source.captureCount, 4);
    cache.clear();
  });
}

PageSnapshotKey _key(String locator) => PageSnapshotKey(
  bookId: 'book',
  locator: locator,
  viewportWidth: 400,
  viewportHeight: 800,
  themeRevision: 1,
  slot: PageSnapshotSlot.current,
);

class _FakeSnapshotSource implements PageSnapshotSource {
  int captureCount = 0;

  @override
  Future<ui.Image> capture(PageSnapshotKey key) async {
    captureCount++;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(1, 1);
    } finally {
      picture.dispose();
    }
  }
}
