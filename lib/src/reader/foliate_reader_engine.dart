import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:leeef_reader/src/reader/reader_content_server.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

class FoliateReaderEngine implements ReaderEngine {
  FoliateReaderEngine({ReaderContentServer? contentServer})
    : _contentServer = contentServer ?? ReaderContentServer();

  final ReaderContentServer _contentServer;
  final StreamController<ReaderEvent> _events =
      StreamController<ReaderEvent>.broadcast();
  Completer<void> _bridgeReady = Completer<void>();
  InAppWebViewController? _webViewController;
  String? _openBookId;
  bool _isClosed = false;

  @override
  Stream<ReaderEvent> get events => _events.stream;

  Uri get readerUri => _contentServer.readerUri;

  Future<void> initialize() => _contentServer.start();

  void attach(InAppWebViewController controller) {
    _ensureOpen();
    _webViewController = controller;
    if (_bridgeReady.isCompleted) _bridgeReady = Completer<void>();
    controller.addJavaScriptHandler(
      handlerName: 'readerEvent',
      callback: (arguments) {
        if (arguments.isNotEmpty && arguments.first is Map) {
          _handleBridgeEvent(Map<String, dynamic>.from(arguments.first as Map));
        }
        return null;
      },
    );
  }

  @override
  Future<ReaderBookInfo> open(
    ReaderBookSource source, {
    String? initialLocator,
  }) async {
    _ensureOpen();
    if (!await source.file.exists()) {
      throw ArgumentError.value(
        source.file.path,
        'source',
        'Book file not found.',
      );
    }
    _contentServer.registerBook(source.bookId, source.file);
    try {
      await _waitForBridge();
      final result = await _call(
        'return await globalThis.leeefReader.open(bookUrl, initialLocator);',
        {
          'bookUrl': _contentServer.bookUri(source.bookId).toString(),
          'initialLocator': initialLocator,
        },
      );
      _openBookId = source.bookId;
      return _bookInfoFrom(result);
    } on Object {
      _contentServer.unregisterBook(source.bookId);
      rethrow;
    }
  }

  @override
  Future<void> goTo(String locator) => _invokeVoid(
    'return await globalThis.leeefReader.goTo(locator);',
    {'locator': locator},
  );

  @override
  Future<void> next() =>
      _invokeVoid('return await globalThis.leeefReader.next();', const {});

  @override
  Future<void> previous() =>
      _invokeVoid('return await globalThis.leeefReader.previous();', const {});

  Future<void> setLayout({
    String flow = 'paginated',
    int maxColumnCount = 1,
    double margin = 24,
  }) {
    if (maxColumnCount < 1) {
      throw ArgumentError.value(
        maxColumnCount,
        'maxColumnCount',
        'Must be at least 1.',
      );
    }
    if (!margin.isFinite || margin < 0) {
      throw ArgumentError.value(margin, 'margin', 'Must be finite and >= 0.');
    }
    return _invokeVoid('return globalThis.leeefReader.setLayout(layout);', {
      'layout': {
        'flow': flow,
        'maxColumnCount': maxColumnCount,
        'margin': margin,
      },
    });
  }

  Future<ReaderLayoutProbe> probeLayout() async {
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return globalThis.leeefReader.probeLayout();',
      const {},
    );
    if (value is! Map) throw const FormatException('Invalid layout probe.');
    final map = Map<String, dynamic>.from(value);
    return ReaderLayoutProbe(
      flow: map['flow'] as String? ?? '',
      maxColumnCount: (map['maxColumnCount'] as num?)?.toInt() ?? 0,
      margin: map['margin'] as String? ?? '',
      renderedSections: (map['renderedSections'] as num?)?.toInt() ?? 0,
      textLength: (map['textLength'] as num?)?.toInt() ?? 0,
      viewportWidth: (map['viewportWidth'] as num?)?.toDouble() ?? 0,
      viewportHeight: (map['viewportHeight'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Exercises the same DOM Range → EPUB CFI path used by real selections.
  /// This is public so platform integration tests can validate native WebViews.
  Future<ReaderSelectionChanged> probeTextSelection() async {
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return await globalThis.leeefReader.probeTextSelection();',
      const {},
    );
    if (value is! Map) throw const FormatException('Invalid selection probe.');
    final map = Map<String, dynamic>.from(value);
    final quote = map['quote'];
    final cfi = map['cfi'];
    if (quote is! String || quote.isEmpty || cfi is! String || cfi.isEmpty) {
      throw const FormatException('Selection probe returned empty data.');
    }
    return ReaderSelectionChanged(quote: quote, cfi: cfi);
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final controller = _webViewController;
    if (controller != null && _bridgeReady.isCompleted) {
      try {
        await _call('return await globalThis.leeefReader.close();', const {});
      } on Object {
        // WebView teardown can race with disposal of the Flutter widget.
      }
    }
    final openBookId = _openBookId;
    if (openBookId != null) _contentServer.unregisterBook(openBookId);
    await _contentServer.close();
    await _events.close();
  }

  Future<void> _invokeVoid(
    String functionBody,
    Map<String, dynamic> arguments,
  ) async {
    _ensureOpen();
    await _waitForBridge();
    await _call(functionBody, arguments);
  }

  Future<dynamic> _call(
    String functionBody,
    Map<String, dynamic> arguments,
  ) async {
    final controller = _webViewController;
    if (controller == null) throw StateError('Reader WebView is not attached.');
    final result = await controller.callAsyncJavaScript(
      functionBody: functionBody,
      arguments: arguments,
    );
    if (result?.error case final error?) {
      _events.add(ReaderFailure(error));
      throw StateError('foliate-js bridge failed: $error');
    }
    return result?.value;
  }

  Future<void> _waitForBridge() async {
    if (_webViewController == null) {
      throw StateError('Reader WebView is not attached.');
    }
    await _bridgeReady.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () =>
          throw TimeoutException('foliate-js bridge did not become ready.'),
    );
  }

  void _handleBridgeEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'ready':
        if (!_bridgeReady.isCompleted) _bridgeReady.complete();
      case 'relocate':
        final cfi = event['cfi'];
        if (cfi is String) {
          _events.add(
            ReaderRelocated(
              cfi: cfi,
              fraction: (event['fraction'] as num?)?.toDouble() ?? 0,
              chapterTitle: event['chapterTitle'] as String?,
            ),
          );
        }
      case 'selection':
        final quote = event['quote'];
        final cfi = event['cfi'];
        if (quote is String && quote.isNotEmpty && cfi is String) {
          _events.add(ReaderSelectionChanged(quote: quote, cfi: cfi));
        }
      case 'error':
        _events.add(
          ReaderFailure(
            event['message']?.toString() ?? 'Unknown reader error.',
          ),
        );
    }
  }

  static ReaderBookInfo _bookInfoFrom(dynamic value) {
    if (value is! Map) throw const FormatException('Invalid book metadata.');
    final map = Map<String, dynamic>.from(value);
    return ReaderBookInfo(
      title: map['title'] as String? ?? '',
      author: map['author'] as String?,
      toc: _tocFrom(map['toc']),
    );
  }

  static List<ReaderTocItem> _tocFrom(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          return ReaderTocItem(
            label: map['label'] as String? ?? '',
            href: map['href'] as String? ?? '',
            children: _tocFrom(map['children']),
          );
        })
        .toList(growable: false);
  }

  void _ensureOpen() {
    if (_isClosed) throw StateError('Reader engine is closed.');
  }
}

class ReaderLayoutProbe {
  const ReaderLayoutProbe({
    required this.flow,
    required this.maxColumnCount,
    required this.margin,
    required this.renderedSections,
    required this.textLength,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final String flow;
  final int maxColumnCount;
  final String margin;
  final int renderedSections;
  final int textLength;
  final double viewportWidth;
  final double viewportHeight;
}
