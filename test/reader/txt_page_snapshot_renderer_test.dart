import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_page_snapshot_renderer.dart';

void main() {
  testWidgets('renders a TXT page at the requested device resolution', (
    tester,
  ) async {
    final image = await renderTxtPageSnapshot(
      text: '第一章\n这是一页用于仿真翻页的文字。',
      size: const Size(200, 300),
      pixelRatio: 2,
      backgroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 16, color: Colors.black),
      textDirection: TextDirection.ltr,
    );
    addTearDown(image.dispose);

    expect(image.width, 400);
    expect(image.height, 600);
  });

  testWidgets('rejects an empty TXT page viewport', (tester) async {
    expect(
      () => renderTxtPageSnapshot(
        text: 'text',
        size: Size.zero,
        pixelRatio: 1,
        backgroundColor: Colors.white,
        textStyle: const TextStyle(),
        textDirection: TextDirection.ltr,
      ),
      throwsArgumentError,
    );
  });
}
