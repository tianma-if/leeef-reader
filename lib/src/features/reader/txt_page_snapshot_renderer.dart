import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<ui.Image> renderTxtPageSnapshot({
  required String text,
  required Size size,
  required double pixelRatio,
  required Color backgroundColor,
  required TextStyle textStyle,
  required TextDirection textDirection,
  EdgeInsets padding = const EdgeInsets.fromLTRB(28, 24, 28, 120),
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
  final contentWidth = (size.width - padding.horizontal).clamp(1.0, 760.0);
  final painter = TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: textDirection,
  )..layout(maxWidth: contentWidth);
  painter.paint(canvas, Offset((size.width - contentWidth) / 2, padding.top));
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
