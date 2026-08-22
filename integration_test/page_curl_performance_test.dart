import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('page curl stays within the 60fps frame budget', (tester) async {
    final currentPage = await _solidImage(const ui.Color(0xFFF7F1E3));
    final nextPage = await _solidImage(const ui.Color(0xFFCEE5D0));
    addTearDown(() {
      currentPage.dispose();
      nextPage.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageCurlSurface(
            currentPage: currentPage,
            nextPage: nextPage,
            onTurnCompleted: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await binding.traceAction(() async {
      for (var index = 0; index < 6; index++) {
        await tester.timedDrag(
          find.byType(PageCurlSurface),
          const Offset(-560, 0),
          const Duration(milliseconds: 420),
        );
        await tester.pumpAndSettle();
      }
    }, reportKey: 'page_curl_timeline');
  });
}

Future<ui.Image> _solidImage(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1080, 2400);
  } finally {
    picture.dispose();
  }
}
