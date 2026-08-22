import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
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
                        onPressed: _page <= 1
                            ? null
                            : () => _goToPage(_page - 1),
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
                        onPressed: _page >= _pageCount
                            ? null
                            : () => _goToPage(_page + 1),
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
