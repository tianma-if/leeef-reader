import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
/// pre-rendering. It exports the current Foliate layout as a platform-neutral
/// model instead of relying on native WebView screenshots.
class FoliatePageSnapshotView extends StatefulWidget {
  const FoliatePageSnapshotView({
    required this.controller,
    required this.book,
    super.key,
    this.layoutSettleDelay = const Duration(milliseconds: 320),
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
        final webView = await _webView.future;
        if (Platform.isIOS) {
          await _setIosSnapshotViewport(webView, key);
        }
        await _engine.open(widget.book, initialLocator: key.locator);
        _bookIsOpen = true;
      }
      if (Platform.isIOS) {
        await _setIosSnapshotViewport(await _webView.future, key);
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
      if (Platform.isAndroid) {
        await webView.callAsyncJavaScript(
          functionBody: '''
            return await new Promise(resolve => requestAnimationFrame(() =>
              requestAnimationFrame(resolve)));
          ''',
        );
      }
      final result = await webView.callAsyncJavaScript(
        functionBody:
            'return await globalThis.leeefReader.captureSnapshotModel(viewport)',
        arguments: {
          'viewport': {
            'width': key.viewportWidth,
            'height': key.viewportHeight,
          },
        },
      );
      return _renderSnapshotModel(
        result?.value,
        width: key.viewportWidth,
        height: key.viewportHeight,
      );
    }();
    final completion = operation.then<void>((_) {}, onError: (_, _) {});
    _navigation = completion;
    try {
      return await operation;
    } finally {
      if (identical(_navigation, completion)) _navigation = null;
    }
  }

  Future<void> _setIosSnapshotViewport(
    InAppWebViewController webView,
    PageSnapshotKey key,
  ) async {
    await webView.evaluateJavascript(
      source:
          '''(() => {
            const width = '${key.viewportWidth}px';
            const height = '${key.viewportHeight}px';
            for (const element of [document.documentElement, document.body,
              document.getElementById('reader')]) {
              if (!element) continue;
              element.style.width = width;
              element.style.height = height;
            }
            window.dispatchEvent(new Event('resize'));
          })()''',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<ui.Image> _renderSnapshotModel(
    dynamic value, {
    required int width,
    required int height,
  }) async {
    final model = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(
      ui.Color((model['background'] as num?)?.toInt() ?? 0xFFFBF8F1),
      ui.BlendMode.src,
    );
    final decodedImages = <ui.Image>[];
    final images = model['images'];
    if (images is List) {
      for (final rawImage in images) {
        if (rawImage is! Map) continue;
        final image = Map<String, dynamic>.from(rawImage);
        final data = image['data'] as String?;
        if (data == null) continue;
        final separator = data.indexOf(',');
        if (separator < 0) continue;
        try {
          final codec = await ui.instantiateImageCodec(
            base64Decode(data.substring(separator + 1)),
          );
          try {
            final decoded = (await codec.getNextFrame()).image;
            decodedImages.add(decoded);
            final left = (image['x'] as num?)?.toDouble() ?? 0;
            final top = (image['y'] as num?)?.toDouble() ?? 0;
            final imageWidth =
                (image['width'] as num?)?.toDouble() ??
                decoded.width.toDouble();
            final imageHeight =
                (image['height'] as num?)?.toDouble() ??
                decoded.height.toDouble();
            canvas.drawImageRect(
              decoded,
              ui.Rect.fromLTWH(
                0,
                0,
                decoded.width.toDouble(),
                decoded.height.toDouble(),
              ),
              ui.Rect.fromLTWH(left, top, imageWidth, imageHeight),
              ui.Paint(),
            );
          } finally {
            codec.dispose();
          }
        } on Object {
          // Unsupported or malformed EPUB images do not block page turning.
        }
      }
    }
    final runs = model['runs'];
    if (runs is! List || runs.isEmpty) {
      throw StateError(
        'EPUB page model contains no visible text: ${model['diagnostics']}',
      );
    }
    for (final rawRun in runs) {
      if (rawRun is! Map) continue;
      final run = Map<String, dynamic>.from(rawRun);
      final text = run['text'] as String? ?? '';
      if (text.isEmpty) continue;
      final weight = ((run['fontWeight'] as num?)?.toInt() ?? 400).clamp(
        100,
        900,
      );
      final builder =
          ui.ParagraphBuilder(
            ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
          )..pushStyle(
            ui.TextStyle(
              color: ui.Color(
                (run['color'] as num?)?.toInt() ??
                    (model['foreground'] as num?)?.toInt() ??
                    0xFF292B29,
              ),
              fontSize: (run['fontSize'] as num?)?.toDouble() ?? 18,
              fontWeight: ui.FontWeight.values[(weight ~/ 100).clamp(1, 9) - 1],
              fontStyle: run['fontStyle'] == 'italic'
                  ? ui.FontStyle.italic
                  : ui.FontStyle.normal,
              letterSpacing: (run['letterSpacing'] as num?)?.toDouble() ?? 0,
            ),
          );
      builder.addText(text);
      final paragraph = builder.build()
        ..layout(
          ui.ParagraphConstraints(
            width: ((run['width'] as num?)?.toDouble() ?? width.toDouble()) + 4,
          ),
        );
      canvas.drawParagraph(
        paragraph,
        ui.Offset(
          (run['x'] as num?)?.toDouble() ?? 0,
          (run['y'] as num?)?.toDouble() ?? 0,
        ),
      );
      paragraph.dispose();
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
      for (final image in decodedImages) {
        image.dispose();
      }
    }
  }
}
