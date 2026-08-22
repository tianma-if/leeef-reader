import 'dart:ui' as ui;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';

/// Snapshot adapter intended for an offstage pre-render WebView.
///
/// [prepare] navigates that replica to the requested adjacent page and waits
/// for its layout to settle. Keeping this separate from the visible reader
/// prevents snapshot generation from flashing during a drag gesture.
class WebViewSnapshotSource implements PageSnapshotSource {
  WebViewSnapshotSource({
    required InAppWebViewController controller,
    required Future<void> Function(PageSnapshotKey key) prepare,
  }) : _controller = controller,
       _prepare = prepare;

  final InAppWebViewController _controller;
  final Future<void> Function(PageSnapshotKey key) _prepare;

  @override
  Future<ui.Image> capture(PageSnapshotKey key) async {
    await _prepare(key);
    final bytes = await _controller.takeScreenshot();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('WebView returned an empty page snapshot.');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}
