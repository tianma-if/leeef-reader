import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';
import 'package:leeef_reader/src/reader/foliate_reader_view.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final FoliateReaderEngine _engine = FoliateReaderEngine();
  StreamSubscription<ReaderEvent>? _eventSubscription;
  Timer? _progressTimer;
  ReaderBookInfo? _bookInfo;
  ReadingLocation? _location;
  ReaderSelectionChanged? _selection;
  Object? _error;
  bool _opening = false;
  bool _controlsVisible = true;

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
      final info = await _engine.open(
        ReaderBookSource(
          bookId: widget.book.id,
          file: File(filePath),
          mediaType: widget.book.mediaType,
        ),
        initialLocator: progress?.locator,
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
        _progressTimer = Timer(
          const Duration(milliseconds: 600),
          () => unawaited(_persistProgress()),
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
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.updateReadingProgress(
      bookId: widget.book.id,
      location: location,
    );
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

  @override
  Widget build(BuildContext context) {
    final progress = _location?.progress ?? 0;
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
        children: [
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
                          onPressed: _bookInfo == null
                              ? null
                              : _engine.previous,
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
                          onPressed: _bookInfo == null ? null : _engine.next,
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
        ],
      ),
    );
  }
}
