import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';
import 'package:leeef_reader/src/features/reader/txt_page_snapshot_renderer.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';

class TxtReaderScreen extends ConsumerStatefulWidget {
  const TxtReaderScreen({required this.book, super.key, this.pageCurlEnabled});

  final BookRecord book;
  final bool? pageCurlEnabled;

  @override
  ConsumerState<TxtReaderScreen> createState() => _TxtReaderScreenState();
}

class _TxtReaderScreenState extends ConsumerState<TxtReaderScreen> {
  TxtReaderDocument? _document;
  int _pageIndex = 0;
  _TxtSelection? _selection;
  Object? _error;
  Timer? _progressTimer;
  String? _lastPersistedLocator;
  bool _preparingTurn = false;
  _TxtCurlTurn? _curlTurn;
  final GlobalKey _bodyKey = GlobalKey();
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  PageCurlController? _pointerCurlController;
  Offset? _lastPointerPosition;
  Duration? _lastPointerTime;
  double _horizontalVelocity = 0;

  bool get _supportsPageCurl =>
      widget.pageCurlEnabled ?? (Platform.isIOS || Platform.isAndroid);

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _curlTurn?.dispose();
    unawaited(_persistProgress());
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final path = widget.book.filePath;
      if (path == null) throw StateError('这本书尚未下载到本机。');
      final document = TxtReaderDocument.decode(await File(path).readAsBytes());
      final repository = await ref.read(libraryRepositoryProvider.future);
      final progress = await repository.getReadingProgress(widget.book.id);
      final offset = parseTxtLocator(
        progress?.locator,
      ).clamp(0, document.text.length);
      _lastPersistedLocator = progress?.locator;
      if (mounted) {
        setState(() {
          _document = document;
          _pageIndex = document.pageIndexForOffset(offset);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _goToPage(int index) {
    final document = _document;
    if (document == null) return;
    final next = index.clamp(0, document.pages.length - 1);
    if (next == _pageIndex) return;
    setState(() {
      _pageIndex = next;
      _selection = null;
    });
    _scheduleProgressSave();
  }

  Future<void> _prepareTurn(
    int targetIndex, {
    bool autoComplete = true,
    PageCurlController? controller,
  }) async {
    final document = _document;
    if (document == null || _preparingTurn || _curlTurn != null) return;
    final target = targetIndex.clamp(0, document.pages.length - 1);
    if (target == _pageIndex) return;
    if (!_supportsPageCurl) {
      _goToPage(target);
      return;
    }

    final renderObject = _bodyKey.currentContext?.findRenderObject();
    final size = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final theme = Theme.of(context);
    final backgroundColor = theme.scaffoldBackgroundColor;
    final textStyle =
        theme.textTheme.bodyLarge?.copyWith(height: 1.8) ??
        const TextStyle(fontSize: 16, height: 1.8);
    final textDirection = Directionality.of(context);

    setState(() => _preparingTurn = true);
    ui.Image? currentImage;
    ui.Image? targetImage;
    try {
      currentImage = await renderTxtPageSnapshot(
        text: document.pages[_pageIndex].text,
        size: size,
        pixelRatio: pixelRatio,
        backgroundColor: backgroundColor,
        textStyle: textStyle,
        textDirection: textDirection,
      );
      targetImage = await renderTxtPageSnapshot(
        text: document.pages[target].text,
        size: size,
        pixelRatio: pixelRatio,
        backgroundColor: backgroundColor,
        textStyle: textStyle,
        textDirection: textDirection,
      );
      if (!mounted) {
        currentImage.dispose();
        targetImage.dispose();
        controller?.dispose();
        return;
      }
      setState(() {
        _curlTurn = _TxtCurlTurn(
          current: currentImage!,
          target: targetImage!,
          targetIndex: target,
          autoComplete: autoComplete,
          controller: controller,
        );
      });
    } on Object {
      currentImage?.dispose();
      targetImage?.dispose();
      controller?.dispose();
      if (mounted) _goToPage(target);
    } finally {
      if (mounted) setState(() => _preparingTurn = false);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.localPosition;
    _pointerDownAt = DateTime.now();
    _lastPointerPosition = event.localPosition;
    _lastPointerTime = event.timeStamp;
    _horizontalVelocity = 0;

    final document = _document;
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    if (document == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize ||
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
    final target = _pageIndex + direction.toInt();
    if (direction == 0 || target < 0 || target >= document.pages.length) return;

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
    if (start == null || startedAt == null) return;
    final isTap =
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
      _pointerCurlController = null;
      _lastPointerPosition = null;
      _lastPointerTime = null;
      return;
    }
    if (!isTap) return;
    final width = _bodyKey.currentContext?.size?.width ?? 0;
    if (width <= 0) return;
    if (event.localPosition.dx <= width * 0.3) {
      unawaited(_prepareTurn(_pageIndex - 1));
    } else if (event.localPosition.dx >= width * 0.7) {
      unawaited(_prepareTurn(_pageIndex + 1));
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _pointerCurlController?.release(horizontalVelocity: 0);
    _pointerCurlController = null;
    _lastPointerPosition = null;
    _lastPointerTime = null;
  }

  void _finishTurn({required bool completed}) {
    final turn = _curlTurn;
    if (turn == null) return;
    setState(() {
      _curlTurn = null;
      if (completed) {
        _pageIndex = turn.targetIndex;
        _selection = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => turn.dispose());
    if (completed) _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 500), () {
      _progressTimer = null;
      unawaited(_persistProgress());
    });
  }

  Future<void> _persistProgress() async {
    final document = _document;
    if (document == null) return;
    final page = document.pages[_pageIndex];
    final locator = txtLocator(page.start);
    if (locator == _lastPersistedLocator) return;
    await (await ref.read(
      libraryRepositoryProvider.future,
    )).updateReadingProgress(
      bookId: widget.book.id,
      location: ReadingLocation(
        locator: locator,
        progress: document.text.isEmpty ? 0 : page.start / document.text.length,
        page: _pageIndex + 1,
      ),
    );
    _lastPersistedLocator = locator;
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final document = _document;
    if (document == null || selection.isCollapsed || !selection.isValid) {
      if (_selection != null) setState(() => _selection = null);
      return;
    }
    final page = document.pages[_pageIndex];
    final start = selection.start.clamp(0, page.text.length);
    final end = selection.end.clamp(0, page.text.length);
    if (start >= end) return;
    setState(() {
      _selection = _TxtSelection(
        quote: page.text.substring(start, end),
        locator: txtLocator(page.start + start),
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
    if (!mounted) return;
    setState(() => _selection = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('书摘已保存')));
  }

  Future<void> _addBookmark() async {
    final document = _document;
    if (document == null) return;
    await (await ref.read(libraryRepositoryProvider.future)).createBookmark(
      bookId: widget.book.id,
      locator: txtLocator(document.pages[_pageIndex].start),
      title: '第 ${_pageIndex + 1} 页',
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('书签已添加')));
    }
  }

  Future<void> _showTableOfContents() async {
    final document = _document;
    if (document == null || document.chapters.isEmpty) return;
    final offset = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('目录')),
            for (final chapter in document.chapters)
              ListTile(
                title: Text(chapter.title),
                onTap: () => Navigator.pop(context, chapter.offset),
              ),
          ],
        ),
      ),
    );
    if (offset != null) _goToPage(document.pageIndexForOffset(offset));
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final page = document?.pages[_pageIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: '添加书签',
            onPressed: document == null ? null : _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: document == null || document.chapters.isEmpty
                ? null
                : _showTableOfContents,
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
          else if (page == null)
            const Center(child: CircularProgressIndicator())
          else
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                child: SingleChildScrollView(
                  key: ValueKey('txt-page-$_pageIndex'),
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 120),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SelectableText(
                        page.text,
                        key: const Key('txt-reader-text'),
                        onSelectionChanged: _onSelectionChanged,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(height: 1.8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (document != null)
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
                        onPressed: _pageIndex == 0 || _preparingTurn
                            ? null
                            : () => _prepareTurn(_pageIndex - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '${_pageIndex + 1} / ${document.pages.length}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: '下一页',
                        onPressed:
                            _pageIndex == document.pages.length - 1 ||
                                _preparingTurn
                            ? null
                            : () => _prepareTurn(_pageIndex + 1),
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
                key: const Key('txt-page-curl'),
                currentPage: turn.current,
                nextPage: turn.target,
                direction: turn.targetIndex > _pageIndex ? 1 : -1,
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

class _TxtCurlTurn {
  const _TxtCurlTurn({
    required this.current,
    required this.target,
    required this.targetIndex,
    required this.autoComplete,
    this.controller,
  });

  final ui.Image current;
  final ui.Image target;
  final int targetIndex;
  final bool autoComplete;
  final PageCurlController? controller;

  void dispose() {
    current.dispose();
    target.dispose();
    controller?.dispose();
  }
}

class _TxtSelection {
  const _TxtSelection({required this.quote, required this.locator});

  final String quote;
  final String locator;
}
