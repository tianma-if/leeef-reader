import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/pdf_reader_screen.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_screen.dart';
import 'package:leeef_reader/src/page_curl/foliate_page_snapshot_view.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';
import 'package:leeef_reader/src/reader/foliate_reader_view.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  Widget build(BuildContext context) => switch (book.mediaType) {
    'application/epub+zip' => EpubReaderScreen(book: book),
    'application/pdf' => PdfReaderScreen(book: book),
    'text/plain' => TxtReaderScreen(book: book),
    _ => Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: Center(child: Text('暂不支持此格式：${book.mediaType}')),
    ),
  };
}

class EpubReaderScreen extends ConsumerStatefulWidget {
  const EpubReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  final FoliateReaderEngine _engine = FoliateReaderEngine();
  final FoliatePageSnapshotController _snapshotController =
      FoliatePageSnapshotController();
  late final PageSnapshotCache _snapshotCache = PageSnapshotCache(
    source: _snapshotController,
  );
  StreamSubscription<ReaderEvent>? _eventSubscription;
  Timer? _progressTimer;
  ReaderBookInfo? _bookInfo;
  ReadingLocation? _location;
  ReaderSelectionChanged? _selection;
  String? _lastPersistedLocation;
  Object? _error;
  bool _opening = false;
  bool _controlsVisible = true;
  bool _preparingTurn = false;
  _CurlTurn? _curlTurn;
  final GlobalKey _bodyKey = GlobalKey();
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  PageCurlController? _pointerCurlController;
  Offset? _lastPointerPosition;
  Duration? _lastPointerTime;
  double _horizontalVelocity = 0;

  bool get _supportsPageCurl => Platform.isIOS || Platform.isAndroid;

  ReaderBookSource? get _bookSource {
    final path = widget.book.filePath;
    if (path == null) return null;
    return ReaderBookSource(
      bookId: widget.book.id,
      file: File(path),
      mediaType: widget.book.mediaType,
    );
  }

  @override
  void initState() {
    super.initState();
    _eventSubscription = _engine.events.listen(_handleReaderEvent);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_persistProgress());
    unawaited(_eventSubscription?.cancel());
    unawaited(_engine.close());
    _curlTurn?.dispose();
    _snapshotCache.clear();
    super.dispose();
  }

  Future<void> _openBook() async {
    if (_opening || _bookInfo != null) return;
    final filePath = widget.book.filePath;
    if (filePath == null) {
      setState(() => _error = StateError('这本书尚未下载到本机。'));
      return;
    }
    _opening = true;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      final progress = await repository.getReadingProgress(widget.book.id);
      if (progress != null) {
        _lastPersistedLocation = ReadingLocation(
          locator: progress.locator,
          progress: progress.progress,
          chapterTitle: progress.chapterTitle,
          page: progress.page,
        ).encode();
      }
      final info = await _engine.open(
        ReaderBookSource(
          bookId: widget.book.id,
          file: File(filePath),
          mediaType: widget.book.mediaType,
        ),
        initialLocator: progress?.locator,
      );
      await repository.updateBookMetadata(
        bookId: widget.book.id,
        title: info.title.isEmpty ? widget.book.title : info.title,
        author: info.author,
        description: widget.book.description,
      );
      if (mounted) setState(() => _bookInfo = info);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _opening = false;
    }
  }

  void _handleReaderEvent(ReaderEvent event) {
    if (!mounted) return;
    switch (event) {
      case ReaderRelocated():
        setState(() {
          _location = ReadingLocation(
            locator: event.cfi,
            progress: event.fraction.clamp(0, 1),
            chapterTitle: event.chapterTitle,
          );
        });
        _progressTimer?.cancel();
        _progressTimer = Timer(const Duration(milliseconds: 600), () {
          _progressTimer = null;
          unawaited(_persistProgress());
        });
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_prefetchAdjacentTextures()),
        );
      case ReaderSelectionChanged():
        setState(() {
          _selection = event;
          _controlsVisible = true;
        });
      case ReaderFailure():
        setState(() => _error = StateError(event.message));
    }
  }

  Future<void> _persistProgress() async {
    final location = _location;
    if (location == null) return;
    final encoded = location.encode();
    if (encoded == _lastPersistedLocation) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.updateReadingProgress(
      bookId: widget.book.id,
      location: location,
    );
    _lastPersistedLocation = encoded;
  }

  Future<void> _saveExcerpt() async {
    final selection = _selection;
    if (selection == null) return;
    final noteController = TextEditingController();
    final note = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存书摘'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selection.quote, maxLines: 5, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: '想法（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, noteController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    noteController.dispose();
    if (note == null || !mounted) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.createExcerpt(
      bookId: widget.book.id,
      locator: selection.cfi,
      quote: selection.quote,
      note: note.trim().isEmpty ? null : note.trim(),
    );
    if (mounted) {
      setState(() => _selection = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('书摘已保存')));
    }
  }

  Future<void> _addBookmark() async {
    final location = _location;
    if (location == null) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.createBookmark(
      bookId: widget.book.id,
      locator: location.locator,
      title: location.chapterTitle,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('书签已添加')));
    }
  }

  Future<void> _showTableOfContents() async {
    final info = _bookInfo;
    if (info == null) return;
    final locator = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('目录')),
            for (final item in info.toc)
              ListTile(
                title: Text(item.label),
                onTap: () => Navigator.pop(context, item.href),
              ),
          ],
        ),
      ),
    );
    if (locator != null) await _engine.goTo(locator);
  }

  Future<void> _prepareTurn(
    bool forward, {
    bool autoComplete = true,
    PageCurlController? controller,
  }) async {
    if (!_supportsPageCurl) {
      await (forward ? _engine.next() : _engine.previous());
      return;
    }
    final location = _location;
    if (location == null || _preparingTurn || _curlTurn != null) return;
    setState(() => _preparingTurn = true);
    ui.Image? currentImage;
    ui.Image? targetImage;
    try {
      final size = MediaQuery.sizeOf(context);
      final common = (
        bookId: widget.book.id,
        locator: location.locator,
        viewportWidth: size.width.round(),
        viewportHeight: size.height.round(),
        themeRevision: 0,
      );
      currentImage = await _snapshotCache.get(
        PageSnapshotKey(
          bookId: common.bookId,
          locator: common.locator,
          viewportWidth: common.viewportWidth,
          viewportHeight: common.viewportHeight,
          themeRevision: common.themeRevision,
          slot: PageSnapshotSlot.current,
        ),
      );
      targetImage = await _snapshotCache.get(
        PageSnapshotKey(
          bookId: common.bookId,
          locator: common.locator,
          viewportWidth: common.viewportWidth,
          viewportHeight: common.viewportHeight,
          themeRevision: common.themeRevision,
          slot: forward ? PageSnapshotSlot.next : PageSnapshotSlot.previous,
        ),
      );
      if (!mounted) {
        currentImage.dispose();
        targetImage.dispose();
        controller?.dispose();
        return;
      }
      setState(
        () => _curlTurn = _CurlTurn(
          current: currentImage!,
          target: targetImage!,
          forward: forward,
          autoComplete: autoComplete,
          controller: controller,
        ),
      );
    } on Object {
      currentImage?.dispose();
      targetImage?.dispose();
      // Snapshot failure is an expected capability boundary. Preserve reading
      // with the ordinary foliate page transition.
      if (identical(_pointerCurlController, controller)) {
        _pointerCurlController = null;
      }
      controller?.dispose();
      if (mounted && autoComplete) {
        await (forward ? _engine.next() : _engine.previous());
      }
    } finally {
      if (mounted) setState(() => _preparingTurn = false);
    }
  }

  void _finishTurn(_CurlTurn turn, {required bool completed}) {
    if (!mounted) return;
    if (completed) {
      unawaited(turn.forward ? _engine.next() : _engine.previous());
    }
    setState(() => _curlTurn = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => turn.dispose());
  }

  Future<void> _prefetchAdjacentTextures() async {
    final location = _location;
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    if (!mounted ||
        !_supportsPageCurl ||
        location == null ||
        _bookInfo == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return;
    }
    final size = renderObject.size;
    final common = (
      bookId: widget.book.id,
      locator: location.locator,
      viewportWidth: size.width.round(),
      viewportHeight: size.height.round(),
      themeRevision: 0,
    );
    try {
      await _snapshotCache.prefetch([
        for (final slot in PageSnapshotSlot.values)
          PageSnapshotKey(
            bookId: common.bookId,
            locator: common.locator,
            viewportWidth: common.viewportWidth,
            viewportHeight: common.viewportHeight,
            themeRevision: common.themeRevision,
            slot: slot,
          ),
      ]);
    } on Object {
      // Prefetch is opportunistic; an edge press can still render on demand.
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final position = _bodyPosition(event.position);
    if (position == null) return;
    _pointerDownPosition = position;
    _pointerDownAt = DateTime.now();
    _lastPointerPosition = position;
    _lastPointerTime = event.timeStamp;
    _horizontalVelocity = 0;
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    if (_bookInfo == null ||
        _location == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize ||
        _preparingTurn ||
        _curlTurn != null) {
      return;
    }
    final size = renderObject.size;
    final direction = position.dx >= size.width * 0.7
        ? 1.0
        : position.dx <= size.width * 0.3
        ? -1.0
        : 0.0;
    if (direction == 0) return;
    final controller = PageCurlController()
      ..begin(position: position, size: size, direction: direction);
    _pointerCurlController = controller;
    unawaited(
      _prepareTurn(direction > 0, autoComplete: false, controller: controller),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final controller = _pointerCurlController;
    if (controller == null) return;
    final position = _bodyPosition(event.position);
    if (position == null) return;
    final previousPosition = _lastPointerPosition;
    final previousTime = _lastPointerTime;
    if (previousPosition != null && previousTime != null) {
      final elapsedMicros = (event.timeStamp - previousTime).inMicroseconds
          .clamp(1, 100000);
      final instantaneous =
          (position.dx - previousPosition.dx) *
          Duration.microsecondsPerSecond /
          elapsedMicros;
      _horizontalVelocity = _horizontalVelocity * 0.58 + instantaneous * 0.42;
    }
    _lastPointerPosition = position;
    _lastPointerTime = event.timeStamp;
    controller.update(position);
  }

  void _handlePointerUp(PointerUpEvent event) {
    final position = _bodyPosition(event.position);
    final start = _pointerDownPosition;
    final startedAt = _pointerDownAt;
    _pointerDownPosition = null;
    _pointerDownAt = null;
    final isTap =
        start != null &&
        startedAt != null &&
        position != null &&
        DateTime.now().difference(startedAt) <=
            const Duration(milliseconds: 350) &&
        (position - start).distance <= 12;
    if (_pointerCurlController case final controller?) {
      if (position != null) controller.update(position);
      controller.release(
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

  Offset? _bodyPosition(Offset globalPosition) {
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.globalToLocal(globalPosition)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _location?.progress ?? 0;
    final bookSource = _bookSource;
    return Scaffold(
      appBar: _controlsVisible
          ? AppBar(
              title: Text(_bookInfo?.title ?? widget.book.title),
              actions: [
                IconButton(
                  tooltip: '添加书签',
                  onPressed: _location == null ? null : _addBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: '目录',
                  onPressed: _bookInfo == null ? null : _showTableOfContents,
                  icon: const Icon(Icons.toc),
                ),
              ],
            )
          : null,
      body: Stack(
        key: _bodyKey,
        children: [
          if (_supportsPageCurl && bookSource != null)
            Positioned.fill(
              child: FoliatePageSnapshotView(
                controller: _snapshotController,
                book: bookSource,
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _controlsVisible = !_controlsVisible),
              child: FoliateReaderView(
                engine: _engine,
                onWebViewCreated: (_) => unawaited(_openBook()),
              ),
            ),
          ),
          if (_supportsPageCurl && _bookInfo != null) ...[
            _buildCurlGestureZone(Alignment.centerLeft),
            _buildCurlGestureZone(Alignment.centerRight),
          ],
          if (_error case final error?)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('无法打开书籍：$error'),
                  ),
                ),
              ),
            ),
          if (_controlsVisible)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(28),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上一页',
                          onPressed: _bookInfo == null || _preparingTurn
                              ? null
                              : () => _prepareTurn(false),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        SizedBox(
                          width: 88,
                          child: Text(
                            '${(progress * 100).round()}%',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          tooltip: '下一页',
                          onPressed: _bookInfo == null || _preparingTurn
                              ? null
                              : () => _prepareTurn(true),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_selection != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: _controlsVisible ? 88 : 16,
              child: Card(
                child: ListTile(
                  title: Text(
                    _selection!.quote,
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
                key: const Key('epub-page-curl'),
                currentPage: turn.current,
                nextPage: turn.target,
                direction: turn.forward ? 1 : -1,
                autoComplete: turn.autoComplete,
                controller: turn.controller,
                onTurnCompleted: () => _finishTurn(turn, completed: true),
                onTurnCancelled: () => _finishTurn(turn, completed: false),
                onUnavailable: () => _finishTurn(turn, completed: true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurlGestureZone(Alignment alignment) => Positioned(
    top: 0,
    bottom: 0,
    left: alignment == Alignment.centerLeft ? 0 : null,
    right: alignment == Alignment.centerRight ? 0 : null,
    width: MediaQuery.sizeOf(context).width * 0.3,
    child: Listener(
      key: Key(
        alignment == Alignment.centerLeft
            ? 'epub-curl-left-zone'
            : 'epub-curl-right-zone',
      ),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: const SizedBox.expand(),
    ),
  );
}

class _CurlTurn {
  const _CurlTurn({
    required this.current,
    required this.target,
    required this.forward,
    required this.autoComplete,
    this.controller,
  });

  final ui.Image current;
  final ui.Image target;
  final bool forward;
  final bool autoComplete;
  final PageCurlController? controller;

  void dispose() {
    current.dispose();
    target.dispose();
    controller?.dispose();
  }
}
