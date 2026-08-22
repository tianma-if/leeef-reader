import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/pdf_page_snapshot_renderer.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
import 'package:leeef_reader/src/page_curl/page_texture_cache.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  final PdfViewerController _controller = PdfViewerController();
  Timer? _progressTimer;
  int _initialPage = 1;
  int _page = 1;
  int _pageCount = 0;
  List<_PdfTocItem> _toc = const [];
  _PdfSelection? _selection;
  String? _lastPersistedLocator;
  Object? _error;
  bool _prepared = false;
  bool _preparingTurn = false;
  _PdfCurlTurn? _curlTurn;
  final GlobalKey _bodyKey = GlobalKey();
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  PageCurlController? _pointerCurlController;
  Offset? _lastPointerPosition;
  Duration? _lastPointerTime;
  double _horizontalVelocity = 0;
  final PageTextureCache<String> _textureCache = PageTextureCache();

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _curlTurn?.dispose();
    _textureCache.dispose();
    unawaited(_persistProgress());
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final path = widget.book.filePath;
      if (path == null || !await File(path).exists()) {
        throw StateError('这本书尚未下载到本机。');
      }
      final progress = await (await ref.read(
        libraryRepositoryProvider.future,
      )).getReadingProgress(widget.book.id);
      final initialPage = parsePdfPageLocator(progress?.locator);
      _lastPersistedLocator = progress?.locator;
      if (mounted) {
        setState(() {
          _initialPage = initialPage;
          _page = initialPage;
          _prepared = true;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    final pageCount = document.pages.length;
    final safePage = _page.clamp(1, pageCount);
    if (mounted) {
      setState(() {
        _pageCount = pageCount;
        _page = safePage;
      });
    }
    unawaited(_loadOutline(document));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_prefetchAdjacentTextures()),
    );
  }

  Future<void> _loadOutline(PdfDocument document) async {
    try {
      final outline = await document.loadOutline();
      final flattened = <_PdfTocItem>[];
      void addNodes(List<PdfOutlineNode> nodes, int depth) {
        for (final node in nodes) {
          final dest = node.dest;
          if (dest != null) {
            flattened.add(
              _PdfTocItem(title: node.title, dest: dest, depth: depth),
            );
          }
          addNodes(node.children, depth + 1);
        }
      }

      addNodes(outline, 0);
      if (mounted) setState(() => _toc = flattened);
    } on Object {
      // An outline is optional in PDF. Page navigation remains available.
    }
  }

  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() {
      _page = page;
      _selection = null;
    });
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 500), () {
      _progressTimer = null;
      unawaited(_persistProgress());
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_prefetchAdjacentTextures()),
    );
  }

  Future<void> _persistProgress() async {
    if (_pageCount < 1) return;
    final locator = pdfPageLocator(_page);
    if (locator == _lastPersistedLocator) return;
    await (await ref.read(
      libraryRepositoryProvider.future,
    )).updateReadingProgress(
      bookId: widget.book.id,
      location: ReadingLocation(
        locator: locator,
        progress: _pageCount == 1 ? 0 : (_page - 1) / (_pageCount - 1),
        page: _page,
      ),
    );
    _lastPersistedLocator = locator;
  }

  Future<void> _onTextSelectionChange(PdfTextSelection selection) async {
    if (!selection.hasSelectedText || !selection.isCopyAllowed) {
      if (mounted && _selection != null) setState(() => _selection = null);
      return;
    }
    final ranges = await selection.getSelectedTextRanges();
    final quote = (await selection.getSelectedText()).trim();
    if (!mounted || ranges.isEmpty || quote.isEmpty) return;
    final first = ranges.first;
    final last = ranges.last;
    setState(() {
      _selection = _PdfSelection(
        quote: quote,
        locator:
            'pdf:${first.pageNumber}:${first.start}-${last.pageNumber}:${last.end}',
      );
    });
  }

  Future<void> _saveExcerpt() async {
    final selection = _selection;
    if (selection == null) return;
    final note = await showExcerptDialog(context, quote: selection.quote);
    if (note == null || !mounted) return;
    await (await ref.read(libraryRepositoryProvider.future)).createExcerpt(
      bookId: widget.book.id,
      locator: selection.locator,
      quote: selection.quote,
      note: note.trim().isEmpty ? null : note.trim(),
    );
    await _controller.textSelectionDelegate.clearTextSelection();
    if (!mounted) return;
    setState(() => _selection = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('书摘已保存')));
  }

  Future<void> _addBookmark() async {
    if (_pageCount < 1) return;
    await (await ref.read(libraryRepositoryProvider.future)).createBookmark(
      bookId: widget.book.id,
      locator: pdfPageLocator(_page),
      title: '第 $_page 页',
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('书签已添加')));
    }
  }

  Future<void> _showTableOfContents() async {
    final item = await showModalBottomSheet<_PdfTocItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('目录')),
            for (final item in _toc)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16 + item.depth * 20,
                  right: 16,
                ),
                title: Text(item.title),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (item != null) await _controller.goToDest(item.dest);
  }

  Future<void> _goToPage(int page) async {
    if (!_controller.isReady || _pageCount < 1) return;
    await _controller.goToPage(pageNumber: page.clamp(1, _pageCount));
  }

  Future<void> _prepareTurn(
    int targetPage, {
    bool autoComplete = true,
    PageCurlController? controller,
  }) async {
    if (!_controller.isReady || _preparingTurn || _curlTurn != null) return;
    final target = targetPage.clamp(1, _pageCount);
    if (target == _page) return;
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    final size = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    setState(() => _preparingTurn = true);
    ui.Image? currentImage;
    ui.Image? targetImage;
    try {
      await _controller.useDocument((document) async {
        final images = await Future.wait([
          _textureCache.get(
            _textureKey(_page, size, pixelRatio, backgroundColor),
            () => renderPdfPageSnapshot(
              page: document.pages[_page - 1],
              size: size,
              pixelRatio: pixelRatio,
              backgroundColor: backgroundColor,
            ),
          ),
          _textureCache.get(
            _textureKey(target, size, pixelRatio, backgroundColor),
            () => renderPdfPageSnapshot(
              page: document.pages[target - 1],
              size: size,
              pixelRatio: pixelRatio,
              backgroundColor: backgroundColor,
            ),
          ),
        ]);
        currentImage = images[0];
        targetImage = images[1];
      });
      if (!mounted || currentImage == null || targetImage == null) {
        currentImage?.dispose();
        targetImage?.dispose();
        controller?.dispose();
        return;
      }
      setState(() {
        _curlTurn = _PdfCurlTurn(
          current: currentImage!,
          target: targetImage!,
          targetPage: target,
          autoComplete: autoComplete,
          controller: controller,
        );
      });
    } on Object {
      currentImage?.dispose();
      targetImage?.dispose();
      controller?.dispose();
      if (mounted && autoComplete) await _goToPage(target);
    } finally {
      if (mounted) setState(() => _preparingTurn = false);
    }
  }

  Future<void> _finishTurn({required bool completed}) async {
    final turn = _curlTurn;
    if (turn == null) return;
    if (completed) await _goToPage(turn.targetPage);
    if (!mounted) return;
    setState(() => _curlTurn = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => turn.dispose());
  }

  Future<void> _prefetchAdjacentTextures() async {
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    if (!mounted ||
        !_controller.isReady ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return;
    }
    final size = renderObject.size;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final pages = <int>{
      _page,
      if (_page > 1) _page - 1,
      if (_page < _pageCount) _page + 1,
    };
    try {
      await _controller.useDocument((document) async {
        await Future.wait([
          for (final pageNumber in pages)
            _textureCache.prefetch(
              _textureKey(pageNumber, size, pixelRatio, backgroundColor),
              () => renderPdfPageSnapshot(
                page: document.pages[pageNumber - 1],
                size: size,
                pixelRatio: pixelRatio,
                backgroundColor: backgroundColor,
              ),
            ),
        ]);
      });
    } on Object {
      // Prefetch is opportunistic; on-demand rendering remains available.
    }
  }

  String _textureKey(
    int pageNumber,
    Size size,
    double pixelRatio,
    Color backgroundColor,
  ) =>
      '${widget.book.id}:$pageNumber:${size.width}x${size.height}:'
      '$pixelRatio:${backgroundColor.toARGB32()}';

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.localPosition;
    _pointerDownAt = DateTime.now();
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    _horizontalVelocity = 0;
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !_controller.isReady ||
        _preparingTurn ||
        _curlTurn != null) {
      return;
    }
    final size = renderObject.size;
    final x = event.localPosition.dx;
    final direction = x >= size.width * 0.7
        ? 1.0
        : x <= size.width * 0.3
        ? -1.0
        : 0.0;
    final target = _page + direction.toInt();
    if (direction == 0 || target < 1 || target > _pageCount) return;
    final controller = PageCurlController()
      ..begin(position: event.localPosition, size: size, direction: direction);
    _pointerCurlController = controller;
    unawaited(
      _prepareTurn(target, autoComplete: false, controller: controller),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final controller = _pointerCurlController;
    if (controller == null) return;
    final previousPosition = _lastPointerPosition;
    final previousTime = _lastPointerTime;
    if (previousPosition != null && previousTime != null) {
      final elapsedMicros = (event.timeStamp - previousTime).inMicroseconds
          .clamp(1, 100000);
      final instantaneous =
          (event.localPosition.dx - previousPosition.dx) *
          Duration.microsecondsPerSecond /
          elapsedMicros;
      _horizontalVelocity = _horizontalVelocity * 0.58 + instantaneous * 0.42;
    }
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    controller.update(event.localPosition);
  }

  void _handlePointerUp(PointerUpEvent event) {
    final start = _pointerDownPosition;
    final startedAt = _pointerDownAt;
    _pointerDownPosition = null;
    _pointerDownAt = null;
    final isTap =
        start != null &&
        startedAt != null &&
        DateTime.now().difference(startedAt) <=
            const Duration(milliseconds: 350) &&
        (event.localPosition - start).distance <= 12;
    if (_pointerCurlController case final controller?) {
      controller
        ..update(event.localPosition)
        ..release(
          horizontalVelocity: _horizontalVelocity,
          forceComplete: isTap,
        );
    }
    _pointerCurlController = null;
    _lastPointerPosition = null;
    _lastPointerTime = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _pointerCurlController?.release(horizontalVelocity: 0);
    _pointerCurlController = null;
    _lastPointerPosition = null;
    _lastPointerTime = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: '添加书签',
            onPressed: _pageCount < 1 ? null : _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: _toc.isEmpty ? null : _showTableOfContents,
            icon: const Icon(Icons.toc),
          ),
        ],
      ),
      body: Stack(
        key: _bodyKey,
        children: [
          if (_error case final error?)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('无法打开书籍：$error'),
              ),
            )
          else if (!_prepared)
            const Center(child: CircularProgressIndicator())
          else
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: PdfViewer.file(
                  widget.book.filePath!,
                  key: const Key('pdf-reader-view'),
                  controller: _controller,
                  initialPageNumber: _initialPage,
                  params: PdfViewerParams(
                    onViewerReady: _onViewerReady,
                    onPageChanged: _onPageChanged,
                    textSelectionParams: PdfTextSelectionParams(
                      onTextSelectionChange: (selection) =>
                          unawaited(_onTextSelectionChange(selection)),
                    ),
                  ),
                ),
              ),
            ),
          if (_pageCount > 0)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(28),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上一页',
                        onPressed: _page <= 1 || _preparingTurn
                            ? null
                            : () => _prepareTurn(_page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '$_page / $_pageCount',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: '下一页',
                        onPressed: _page >= _pageCount || _preparingTurn
                            ? null
                            : () => _prepareTurn(_page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_selection case final selection?)
            Positioned(
              left: 16,
              right: 16,
              bottom: 88,
              child: Card(
                child: ListTile(
                  title: Text(
                    selection.quote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: _saveExcerpt,
                    icon: const Icon(Icons.format_quote),
                    label: const Text('摘录'),
                  ),
                ),
              ),
            ),
          if (_curlTurn case final turn?)
            Positioned.fill(
              child: PageCurlSurface(
                key: const Key('pdf-page-curl'),
                currentPage: turn.current,
                nextPage: turn.target,
                direction: turn.targetPage > _page ? 1 : -1,
                autoComplete: turn.autoComplete,
                controller: turn.controller,
                onTurnCompleted: () => _finishTurn(completed: true),
                onTurnCancelled: () => _finishTurn(completed: false),
                onUnavailable: () => _finishTurn(completed: true),
              ),
            ),
        ],
      ),
    );
  }
}

int parsePdfPageLocator(String? locator) {
  if (locator == null || !locator.startsWith('pdf:')) return 1;
  final page = int.tryParse(locator.substring(4).split(':').first);
  return page == null || page < 1 ? 1 : page;
}

String pdfPageLocator(int page) => 'pdf:$page';

class _PdfTocItem {
  const _PdfTocItem({
    required this.title,
    required this.dest,
    required this.depth,
  });

  final String title;
  final PdfDest dest;
  final int depth;
}

class _PdfSelection {
  const _PdfSelection({required this.quote, required this.locator});

  final String quote;
  final String locator;
}

class _PdfCurlTurn {
  const _PdfCurlTurn({
    required this.current,
    required this.target,
    required this.targetPage,
    required this.autoComplete,
    this.controller,
  });

  final ui.Image current;
  final ui.Image target;
  final int targetPage;
  final bool autoComplete;
  final PageCurlController? controller;

  void dispose() {
    current.dispose();
    target.dispose();
    controller?.dispose();
  }
}
