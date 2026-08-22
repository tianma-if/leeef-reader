import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';

class TxtReaderScreen extends ConsumerStatefulWidget {
  const TxtReaderScreen({required this.book, super.key});

  final BookRecord book;

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

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
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
                        onPressed: _pageIndex == 0
                            ? null
                            : () => _goToPage(_pageIndex - 1),
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
                        onPressed: _pageIndex == document.pages.length - 1
                            ? null
                            : () => _goToPage(_pageIndex + 1),
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
        ],
      ),
    );
  }
}

class _TxtSelection {
  const _TxtSelection({required this.quote, required this.locator});

  final String quote;
  final String locator;
}
