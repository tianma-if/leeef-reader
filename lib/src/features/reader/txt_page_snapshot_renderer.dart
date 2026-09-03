import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/reader/txt_page_layout.dart';

Future<ui.Image> renderTxtPageSnapshot({
  required String text,
  required Size size,
  required double pixelRatio,
  required Color backgroundColor,
  required TextStyle textStyle,
  required TextDirection textDirection,
  EdgeInsets padding = const EdgeInsets.fromLTRB(24, 24, 24, 72),
  TextScaler textScaler = TextScaler.noScaling,
  TextAlign textAlign = TextAlign.start,
}) async {
  if (size.isEmpty || !size.isFinite) {
    throw ArgumentError.value(size, 'size', 'Must be finite and non-empty.');
  }
  final safePixelRatio = pixelRatio.clamp(1.0, 3.0);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(safePixelRatio)
    ..drawRect(Offset.zero & size, Paint()..color = backgroundColor)
    ..save()
    ..clipRect(Offset.zero & size);
  final contentWidth =
      (size.width - padding.horizontal - TxtPageLayout.caretMargin).clamp(
        1.0,
        double.infinity,
      );
  final painter = TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: textDirection,
    textScaler: textScaler,
    textAlign: textAlign,
    strutStyle: StrutStyle.fromTextStyle(textStyle),
  )..layout(maxWidth: contentWidth);
  painter.paint(canvas, Offset(padding.left, padding.top));
  painter.dispose();
  canvas.restore();
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(
      (size.width * safePixelRatio).ceil(),
      (size.height * safePixelRatio).ceil(),
    );
  } finally {
    picture.dispose();
  }
}
