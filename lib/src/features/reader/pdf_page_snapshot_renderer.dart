import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

Future<ui.Image> renderPdfPageSnapshot({
  required PdfPage page,
  required Size size,
  required double pixelRatio,
  required Color backgroundColor,
}) async {
  final outputWidth = (size.width * pixelRatio).round().clamp(1, 4096);
  final outputHeight = (size.height * pixelRatio).round().clamp(1, 4096);
  final scale = math.min(outputWidth / page.width, outputHeight / page.height);
  final pageWidth = (page.width * scale).round().clamp(1, outputWidth);
  final pageHeight = (page.height * scale).round().clamp(1, outputHeight);
  final rendered = await page.render(
    fullWidth: pageWidth.toDouble(),
    fullHeight: pageHeight.toDouble(),
    backgroundColor: 0xFFFFFFFF,
  );
  if (rendered == null) throw StateError('PDF page rendering returned null.');
  ui.Image? pageImage;
  try {
    pageImage = await rendered.createImage(pixelSizeThreshold: 4096);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(backgroundColor, BlendMode.src);
    final left = (outputWidth - pageImage.width) / 2;
    final top = (outputHeight - pageImage.height) / 2;
    canvas.drawImage(pageImage, Offset(left, top), Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(outputWidth, outputHeight);
    } finally {
      picture.dispose();
    }
  } finally {
    pageImage?.dispose();
    rendered.dispose();
  }
}
