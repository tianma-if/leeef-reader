import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_curl/page_texture_cache.dart';

void main() {
  test(
    'prefetch deduplicates rendering and get returns an owned clone',
    () async {
      final cache = PageTextureCache<String>();
      var renders = 0;
      Future<ui.Image> render() async {
        renders++;
        return _image();
      }

      await cache.prefetch('page-1', render);
      final first = await cache.get('page-1', render);
      final second = await cache.get('page-1', render);

      expect(renders, 1);
      expect(first, isNot(same(second)));
      first.dispose();
      second.dispose();
      cache.clear();
    },
  );
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(2, 2);
  } finally {
    picture.dispose();
  }
}
