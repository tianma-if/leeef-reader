import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_slide/page_slide_surface.dart';

void main() {
  testWidgets('adjacent pages share one continuous seam while sliding', (
    tester,
  ) async {
    final current = await _solidImage(const Color(0xFFFFFFFF));
    final next = await _solidImage(const Color(0xFF000000));
    addTearDown(current.dispose);
    addTearDown(next.dispose);
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 480,
            child: PageSlideSurface(
              currentPage: current,
              nextPage: next,
              direction: 1,
              onTurnCompleted: () => completed = true,
            ),
          ),
        ),
      ),
    );

    final start = tester.getCenter(find.byType(PageSlideSurface));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();

    final currentRect = tester.getRect(find.byType(RawImage).first);
    final nextRect = tester.getRect(find.byType(RawImage).last);
    expect(currentRect.right, closeTo(nextRect.left, 1));
    expect(completed, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets('a tap-driven slide auto-completes onto the incoming page', (
    tester,
  ) async {
    final current = await _solidImage(const Color(0xFFFFFFFF));
    final next = await _solidImage(const Color(0xFF000000));
    addTearDown(current.dispose);
    addTearDown(next.dispose);
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: PageSlideSurface(
            currentPage: current,
            nextPage: next,
            autoComplete: true,
            onTurnCompleted: () => completed = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });
}

Future<ui.Image> _solidImage(Color color) {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 32, 48), Paint()..color = color);
  return recorder.endRecording().toImage(32, 48);
}
