import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';
import 'package:leeef_reader/src/reader/foliate_reader_view.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

/// Controls a dedicated, non-interactive foliate WebView used only to render
/// page textures. Keep the matching [FoliatePageSnapshotView] mounted while
/// snapshots are requested.
class FoliatePageSnapshotController implements PageSnapshotSource {
  final Completer<_FoliatePageSnapshotViewState> _binding = Completer();
  _FoliatePageSnapshotViewState? _state;

  @override
  Future<ui.Image> capture(PageSnapshotKey key) async {
    final state = _state ?? await _binding.future;
    if (!state.mounted) {
      throw StateError('Foliate snapshot view is no longer mounted.');
    }
    return state.capture(key);
  }

  void _bind(_FoliatePageSnapshotViewState state) {
    _state = state;
    if (!_binding.isCompleted) _binding.complete(state);
  }

  void _unbind(_FoliatePageSnapshotViewState state) {
    if (identical(_state, state)) _state = null;
  }
}

/// An independently laid-out foliate WebView for previous/current/next page
/// pre-rendering. It must remain mounted with a concrete Flutter layout while
/// `takeScreenshot` runs; the snapshot key supplies the explicit capture size.
class FoliatePageSnapshotView extends StatefulWidget {
  const FoliatePageSnapshotView({
    required this.controller,
    required this.book,
    super.key,
    this.layoutSettleDelay = const Duration(milliseconds: 80),
  });

  final FoliatePageSnapshotController controller;
  final ReaderBookSource book;
  final Duration layoutSettleDelay;

  @override
  State<FoliatePageSnapshotView> createState() =>
      _FoliatePageSnapshotViewState();
}

class _FoliatePageSnapshotViewState extends State<FoliatePageSnapshotView> {
  final FoliateReaderEngine _engine = FoliateReaderEngine();
  final Completer<InAppWebViewController> _webView = Completer();
  bool _bookIsOpen = false;
  Future<void>? _navigation;

  @override
  void initState() {
    super.initState();
    widget.controller._bind(this);
  }

  @override
  void didUpdateWidget(FoliatePageSnapshotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._unbind(this);
      widget.controller._bind(this);
    }
    if (oldWidget.book.bookId != widget.book.bookId ||
        oldWidget.book.file.path != widget.book.file.path) {
      _bookIsOpen = false;
    }
  }

  @override
  void dispose() {
    widget.controller._unbind(this);
    unawaited(_engine.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FoliateReaderView(
        engine: _engine,
        onWebViewCreated: (controller) {
          if (!_webView.isCompleted) _webView.complete(controller);
        },
      ),
    );
  }

  Future<ui.Image> capture(PageSnapshotKey key) async {
    if (key.bookId != widget.book.bookId) {
      throw ArgumentError.value(key.bookId, 'key', 'Snapshot book mismatch.');
    }

    // Serialize navigation because a WebView has only one active layout.
    final previous = _navigation;
    final operation = () async {
      if (previous != null) await previous;
      if (_bookIsOpen) {
        await _engine.goTo(key.locator);
      } else {
        await _webView.future;
        await _engine.open(widget.book, initialLocator: key.locator);
        _bookIsOpen = true;
      }
      switch (key.slot) {
        case PageSnapshotSlot.previous:
          await _engine.previous();
          break;
        case PageSnapshotSlot.current:
          break;
        case PageSnapshotSlot.next:
          await _engine.next();
          break;
      }
      // open/goTo resolve after foliate has applied navigation. Relocation is
      // intentionally not used as a barrier: hidden WKWebViews can coalesce
      // that event even though the requested layout is already available.
      await Future<void>.delayed(widget.layoutSettleDelay);

      final webView = await _webView.future;
      final metrics = await webView.evaluateJavascript(
        source: '''({
          width: window.innerWidth,
          height: window.innerHeight,
          readyState: document.readyState
        })''',
      );
      final metricMap = metrics is Map
          ? Map<String, dynamic>.from(metrics)
          : const <String, dynamic>{};
      final reportedWidth = (metricMap['width'] as num?)?.toDouble() ?? 0;
      final reportedHeight = (metricMap['height'] as num?)?.toDouble() ?? 0;
      final width = reportedWidth > 0
          ? reportedWidth
          : key.viewportWidth.toDouble();
      final height = reportedHeight > 0
          ? reportedHeight
          : key.viewportHeight.toDouble();
      final bytes = await webView.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          afterScreenUpdates: true,
          compressFormat: CompressFormat.PNG,
          rect: InAppWebViewRect(x: 0, y: 0, width: width, height: height),
        ),
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Pre-render WebView returned an empty snapshot: $metrics',
        );
      }
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }();
    final completion = operation.then<void>((_) {}, onError: (_, _) {});
    _navigation = completion;
    try {
      return await operation;
    } finally {
      if (identical(_navigation, completion)) _navigation = null;
    }
  }
}
