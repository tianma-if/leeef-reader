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
  final Completer<void> _webViewAttached = Completer<void>();
  Completer<void> _bridgeReady = Completer<void>();
  InAppWebViewController? _webViewController;
  String? _openBookId;
  bool _isClosed = false;

  @override
  Stream<ReaderEvent> get events => _events.stream;

  Uri get readerUri => _contentServer.readerUri;

  Future<void> initialize() => _contentServer.start();

  void attach(InAppWebViewController controller) {
    // Windows platform views can finish initialization after their Flutter
    // widget has already been disposed. A late native callback must not revive
    // or fail a closed reader engine.
    if (_isClosed) return;
    _webViewController = controller;
    if (!_webViewAttached.isCompleted) _webViewAttached.complete();
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

  Future<void> historyBack() =>
      _invokeVoid('return globalThis.leeefReader.historyBack();', const {});

  Future<void> historyForward() =>
      _invokeVoid('return globalThis.leeefReader.historyForward();', const {});

  Future<({bool canGoBack, bool canGoForward})> historyState() async {
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return globalThis.leeefReader.historyState();',
      const {},
    );
    final map = value is Map ? Map<String, dynamic>.from(value) : const {};
    return (
      canGoBack: map['canGoBack'] == true,
      canGoForward: map['canGoForward'] == true,
    );
  }

  Future<void> setLayout({
    String flow = 'paginated',
    int maxColumnCount = 1,
    double margin = 24,
    String pageTurnEffect = 'slide',
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
        'pageTurnEffect': pageTurnEffect,
      },
    });
  }

  Future<void> setTheme({
    required String foreground,
    required String background,
    required double fontSize,
    required double lineHeight,
    required String fontFamily,
    required int fontWeight,
    double headingScale = 1.25,
    required double letterSpacing,
    required double paragraphSpacing,
    double textIndent = 0,
    required String textAlign,
    String writingMode = 'horizontal-tb',
    bool preserveBookStyles = true,
    bool eInkMode = false,
    bool codeHighlight = true,
    String backgroundImage = '',
    double backgroundOpacity = .18,
    double backgroundBlur = 0,
    String backgroundFit = 'cover',
    String importedFontName = '',
    String importedFontData = '',
    String customCss = '',
  }) => _invokeVoid('return globalThis.leeefReader.setTheme(theme);', {
    'theme': {
      'foreground': foreground,
      'background': background,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight,
      'headingScale': headingScale,
      'letterSpacing': letterSpacing,
      'paragraphSpacing': paragraphSpacing,
      'textIndent': textIndent,
      'textAlign': textAlign,
      'writingMode': writingMode,
      'preserveBookStyles': preserveBookStyles,
      'eInkMode': eInkMode,
      'codeHighlight': codeHighlight,
      'backgroundImage': backgroundImage,
      'backgroundOpacity': backgroundOpacity,
      'backgroundBlur': backgroundBlur,
      'backgroundFit': backgroundFit,
      'importedFontName': importedFontName,
      'importedFontData': importedFontData,
      'customCSS': customCss,
    },
  });

  Future<List<ReaderSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return await globalThis.leeefReader.search(query);',
      {'query': trimmed},
    );
    if (value is! List) throw const FormatException('Invalid search result.');
    return value
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          return ReaderSearchResult(
            label: map['label'] as String? ?? '',
            cfi: map['cfi'] as String? ?? '',
            excerpt: map['excerpt'] as String? ?? '',
          );
        })
        .where((item) => item.cfi.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> clearSearch() =>
      _invokeVoid('return globalThis.leeefReader.clearSearch();', const {});

  Future<String> currentText() async {
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return globalThis.leeefReader.currentText();',
      const {},
    );
    return value is String ? value : '';
  }

  Future<String> bookText({int maxCharacters = 2000000}) async {
    if (maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters');
    }
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return await globalThis.leeefReader.bookText(options);',
      {
        'options': {'maxCharacters': maxCharacters},
      },
    );
    return value is String ? value : '';
  }

  Future<List<String>> visibleTextNodes() async {
    _ensureOpen();
    await _waitForBridge();
    final value = await _call(
      'return globalThis.leeefReader.visibleTextNodes();',
      const {},
    );
    return value is List
        ? value.whereType<String>().toList(growable: false)
        : const [];
  }

  Future<void> applyVisibleTextNodes(List<String> texts) => _invokeVoid(
    'return globalThis.leeefReader.applyVisibleTextNodes(texts);',
    {'texts': texts},
  );

  Future<void> setBookJavaScriptEnabled(bool enabled) => _invokeVoid(
    'return globalThis.leeefReader.setBookJavaScriptEnabled(enabled);',
    {'enabled': enabled},
  );

  Future<void> highlightTtsSentence(String? sentence) => _invokeVoid(
    'return globalThis.leeefReader.highlightTtsSentence(sentence);',
    {'sentence': sentence ?? ''},
  );

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
      animated: map['animated'] == true,
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
    await _webViewAttached.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw TimeoutException('Reader WebView was not attached in time.'),
    );
    _ensureOpen();
    await _bridgeReady.future.timeout(
      const Duration(seconds: 30),
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
      case 'selection-cleared':
        _events.add(const ReaderSelectionCleared());
      case 'external-link':
        final href = event['href'];
        if (href is String && href.isNotEmpty) {
          _events.add(ReaderExternalLinkActivated(href));
        }
      case 'image':
        final source = event['source'];
        if (source is String && source.isNotEmpty) {
          _events.add(
            ReaderImageActivated(
              source,
              description: event['description'] as String?,
            ),
          );
        }
      case 'footnote':
        final text = event['text'];
        if (text is String && text.isNotEmpty) {
          _events.add(
            ReaderFootnoteActivated(
              title: event['title'] as String? ?? '脚注',
              text: text,
            ),
          );
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
    required this.animated,
    required this.renderedSections,
    required this.textLength,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final String flow;
  final int maxColumnCount;
  final String margin;
  final bool animated;
  final int renderedSections;
  final int textLength;
  final double viewportWidth;
  final double viewportHeight;
}

class ReaderSearchResult {
  const ReaderSearchResult({
    required this.label,
    required this.cfi,
    required this.excerpt,
  });

  final String label;
  final String cfi;
  final String excerpt;
}
