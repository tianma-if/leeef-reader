import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/ai/translation_sheet.dart';
import 'package:leeef_reader/src/features/ai/ai_assistant_screen.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/pdf_page_snapshot_renderer.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/features/notes/excerpt_share_card_screen.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
import 'package:leeef_reader/src/page_curl/page_texture_cache.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';
import 'package:leeef_reader/src/reader/reader_navigation_history.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';
import 'package:leeef_reader/src/tts/configured_tts_engine.dart';
import 'package:leeef_reader/src/tts/tts_controls_sheet.dart';
import 'package:leeef_reader/src/tts/tts_media_controls.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  const PdfReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  final PdfViewerController _controller = PdfViewerController();
  late final PdfTextSearcher _textSearcher = PdfTextSearcher(_controller);
  Timer? _progressTimer;
  Timer? _clockTimer;
  int _initialPage = 1;
  int _page = 1;
  int _pageCount = 0;
  List<PdfOutlineEntry> _toc = const [];
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
  LibraryRepository? _repository;
  bool _searchActive = false;
  DateTime? _sessionStartedAt;
  ReaderPreferences _preferences = const ReaderPreferences();
  bool _controlsVisible = true;
  DateTime? _lastWheelTurn;
  final ReaderNavigationHistory _history = ReaderNavigationHistory();
  late final SystemTtsController _ttsController = SystemTtsController(
    engine: ConfiguredTtsEngine(),
    mediaControls: TtsMediaControlBridge.instance,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _textSearcher.addListener(_onSearchChanged);
    unawaited(_ttsController.initialize());
    _ttsController.addListener(_onTtsChanged);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          (_preferences.headerContent == 'time' ||
              _preferences.footerContent == 'time')) {
        setState(() {});
      }
    });
    unawaited(_prepare());
  }

  void _onTtsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    _curlTurn?.dispose();
    _textureCache.dispose();
    _textSearcher.dispose();
    final repository = _repository;
    final startedAt = _sessionStartedAt;
    if (repository != null && startedAt != null) {
      unawaited(
        repository.recordReadingSession(
          bookId: widget.book.id,
          startedAt: startedAt,
          endedAt: DateTime.now(),
        ),
      );
    }
    _ttsController.dispose();
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _pageCount < 1) return false;
    final key = event.logicalKey;
    if ((HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        key == LogicalKeyboardKey.keyF) {
      unawaited(_showSearch());
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      unawaited(_goToPage(_page + 1));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      unawaited(_goToPage(_page - 1));
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeUp) {
      unawaited(_goToPage(_page - 1));
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeDown) {
      unawaited(_goToPage(_page + 1));
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _controlsVisible = !_controlsVisible);
      return true;
    }
    return false;
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prepare() async {
    try {
      final path = widget.book.filePath;
      if (path == null || !await File(path).exists()) {
        throw StateError('这本书尚未下载到本机。');
      }
      final repository = await ref.read(libraryRepositoryProvider.future);
      final preferences = await ReaderPreferences.load();
      await _applyReadingState(preferences);
      _repository = repository;
      final progress = await repository.getReadingProgress(widget.book.id);
      final initialPage = parsePdfPageLocator(progress?.locator);
      _lastPersistedLocator = progress?.locator;
      if (mounted) {
        setState(() {
          _initialPage = initialPage;
          _page = initialPage;
          _prepared = true;
          _preferences = preferences;
          _history.reset(initialPage);
          _sessionStartedAt ??= DateTime.now();
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _applyReadingState(ReaderPreferences preferences) async {
    await WakelockPlus.toggle(enable: preferences.keepAwake);
    await SystemChrome.setEnabledSystemUIMode(
      preferences.fullscreen
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _showReadingSettings() async {
    final strings = AppStrings.of(context);
    var draft = _preferences;
    final result = await showModalBottomSheet<ReaderPreferences>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('PDF 阅读设置'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'paginated',
                      label: Text(strings.text('横向分页')),
                    ),
                    ButtonSegment(
                      value: 'scrolled',
                      label: Text(strings.text('连续滚动')),
                    ),
                  ],
                  selected: {draft.flow},
                  onSelectionChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(flow: value.single),
                  ),
                ),
                Slider(
                  value: draft.tapZoneRatio,
                  min: .15,
                  max: .45,
                  divisions: 6,
                  label: '${(draft.tapZoneRatio * 100).round()}%',
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(tapZoneRatio: value),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('点击翻页区域宽度')),
                ),
                for (final option
                    in <(String, bool, ReaderPreferences Function(bool))>[
                      (
                        '左右点击区域互换',
                        draft.swapTapZones,
                        (v) => draft.copyWith(swapTapZones: v),
                      ),
                      (
                        '音量键翻页',
                        draft.volumeKeyPaging,
                        (v) => draft.copyWith(volumeKeyPaging: v),
                      ),
                      (
                        '鼠标滚轮翻页',
                        draft.mouseWheelPaging,
                        (v) => draft.copyWith(mouseWheelPaging: v),
                      ),
                      (
                        '阅读时屏幕常亮',
                        draft.keepAwake,
                        (v) => draft.copyWith(keepAwake: v),
                      ),
                      (
                        '沉浸全屏',
                        draft.fullscreen,
                        (v) => draft.copyWith(fullscreen: v),
                      ),
                      (
                        '显示页眉',
                        draft.showHeader,
                        (v) => draft.copyWith(showHeader: v),
                      ),
                      (
                        '显示页脚',
                        draft.showFooter,
                        (v) => draft.copyWith(showFooter: v),
                      ),
                    ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.text(option.$1)),
                    value: option.$2,
                    onChanged: (value) =>
                        setDialogState(() => draft = option.$3(value)),
                  ),
                if (draft.showHeader)
                  DropdownButtonFormField<String>(
                    initialValue: draft.headerContent,
                    decoration: InputDecoration(
                      labelText: strings.text('页眉内容'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'title',
                        child: Text(strings.text('书名')),
                      ),
                      DropdownMenuItem(
                        value: 'chapter',
                        child: Text(strings.text('章节名')),
                      ),
                      DropdownMenuItem(
                        value: 'progress',
                        child: Text(strings.text('阅读进度')),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(headerContent: value),
                    ),
                  ),
                if (draft.showFooter)
                  DropdownButtonFormField<String>(
                    initialValue: draft.footerContent,
                    decoration: InputDecoration(
                      labelText: strings.text('页脚内容'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'progress',
                        child: Text(strings.text('阅读进度')),
                      ),
                      DropdownMenuItem(
                        value: 'page',
                        child: Text(strings.text('页码')),
                      ),
                      DropdownMenuItem(
                        value: 'chapter',
                        child: Text(strings.text('章节名')),
                      ),
                      DropdownMenuItem(
                        value: 'time',
                        child: Text(strings.text('当前时间')),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(footerContent: value),
                    ),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, draft),
                  child: Text(strings.text('应用')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    await result.save();
    await _applyReadingState(result);
    if (mounted) setState(() => _preferences = result);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_preferences.mouseWheelPaging ||
        event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() < 2) {
      return;
    }
    final now = DateTime.now();
    if (_lastWheelTurn != null &&
        now.difference(_lastWheelTurn!) < const Duration(milliseconds: 220)) {
      return;
    }
    _lastWheelTurn = now;
    unawaited(_goToPage(_page + (event.scrollDelta.dy > 0 ? 1 : -1)));
  }

  Future<void> _showReaderContextMenu(Offset position) async {
    final strings = AppStrings.of(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'previous', child: Text(strings.text('上一页'))),
        PopupMenuItem(value: 'next', child: Text(strings.text('下一页'))),
        PopupMenuItem(value: 'search', child: Text(strings.text('书内搜索'))),
        PopupMenuItem(value: 'settings', child: Text(strings.text('阅读设置'))),
        PopupMenuItem(value: 'bookmark', child: Text(strings.text('添加书签'))),
      ],
    );
    switch (action) {
      case 'previous':
        unawaited(_goToPage(_page - 1));
      case 'next':
        unawaited(_goToPage(_page + 1));
      case 'search':
        unawaited(_showSearch());
      case 'settings':
        unawaited(_showReadingSettings());
      case 'bookmark':
        unawaited(_addBookmark());
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
      final flattened = <PdfOutlineEntry>[];
      void addNodes(List<PdfOutlineNode> nodes, int depth) {
        for (final node in nodes) {
          final dest = node.dest;
          if (dest != null) {
            flattened.add(
              PdfOutlineEntry(title: node.title, dest: dest, depth: depth),
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
      _history.visit(page);
      _selection = null;
    });
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(HapticFeedback.selectionClick());
    }
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
    final repository = _repository;
    if (_pageCount < 1 || repository == null) return;
    final locator = pdfPageLocator(_page);
    if (locator == _lastPersistedLocator) return;
    await repository.updateReadingProgress(
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
    final strings = AppStrings.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.text('书摘已保存'))));
  }

  Future<void> _addBookmark() async {
    if (_pageCount < 1) return;
    final strings = AppStrings.of(context);
    await (await ref.read(libraryRepositoryProvider.future)).createBookmark(
      bookId: widget.book.id,
      locator: pdfPageLocator(_page),
      title: strings.pageNumber(_page),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('书签已添加'))));
    }
  }

  Future<void> _showTableOfContents() async {
    final strings = AppStrings.of(context);
    final item = await showModalBottomSheet<PdfOutlineEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(strings.text('目录'))),
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

  Future<void> _showSearch() async {
    final strings = AppStrings.of(context);
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('书内搜索')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: strings.text('关键词')),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(strings.text('搜索')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null || query.isEmpty) return;
    setState(() => _searchActive = true);
    _textSearcher.startTextSearch(query, searchImmediately: true);
  }

  void _closeSearch() {
    _textSearcher.resetTextSearch();
    setState(() => _searchActive = false);
  }

  Future<void> _showTts() async {
    final selected = _selection?.quote;
    final pageText = selected == null
        ? await _textSearcher.loadText(pageNumber: _page)
        : null;
    if (!mounted) return;
    await showTtsControlsSheet(
      context,
      controller: _ttsController,
      text: selected ?? pageText?.fullText ?? '',
    );
  }

  Future<void> _translateSelection() async {
    final selection = _selection;
    if (selection == null) return;
    final pageText = await _textSearcher.loadText(pageNumber: _page);
    if (!mounted) return;
    await showTranslationSheet(
      context,
      text: selection.quote,
      contextText: pageText?.fullText ?? selection.quote,
    );
  }

  Future<void> _handleSelectionAction(String action) async {
    final selection = _selection;
    if (selection == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: selection.quote));
      case 'web':
        await launchUrl(
          Uri.https('www.google.com', '/search', {'q': selection.quote}),
          mode: LaunchMode.externalApplication,
        );
      case 'ai':
        final pageText = await _textSearcher.loadText(pageNumber: _page);
        if (!mounted) return;
        final strings = AppStrings.of(context);
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AiAssistantScreen(
              title: '${widget.book.title} · ${strings.text('选中文本')}',
              contextText:
                  '选中文本：${selection.quote}\n\n页面上下文：${pageText?.fullText ?? ''}',
            ),
          ),
        );
      case 'card':
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ExcerptShareCardScreen(
              quote: selection.quote,
              book: widget.book,
            ),
          ),
        );
    }
  }

  Future<void> _openAi(String action) async {
    final buffer = StringBuffer();
    for (var page = 1; page <= _pageCount; page++) {
      final text = await _textSearcher.loadText(pageNumber: page);
      if (text?.fullText.trim().isNotEmpty ?? false) {
        buffer.writeln(text!.fullText);
      }
    }
    if (!mounted || buffer.isEmpty) return;
    final source = buffer.toString();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => action == 'translate'
            ? FullTranslationScreen(
                title: widget.book.title,
                sourceText: source,
              )
            : AiAssistantScreen(
                title: '${widget.book.title} · AI',
                contextText: source,
              ),
      ),
    );
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
    final position = _bodyPosition(event.position);
    if (position == null) return;
    _pointerDownPosition = position;
    _pointerDownAt = DateTime.now();
    _lastPointerPosition = position;
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
    final x = position.dx;
    var direction = x >= size.width * (1 - _preferences.tapZoneRatio)
        ? 1.0
        : x <= size.width * _preferences.tapZoneRatio
        ? -1.0
        : 0.0;
    if (_preferences.swapTapZones) direction = -direction;
    final target = _page + direction.toInt();
    if (direction == 0 || target < 1 || target > _pageCount) return;
    final controller = PageCurlController()
      ..begin(position: position, size: size, direction: direction);
    _pointerCurlController = controller;
    unawaited(
      _prepareTurn(target, autoComplete: false, controller: controller),
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
    final strings = AppStrings.of(context);
    final progress = _pageCount == 0 ? 0.0 : _page / _pageCount;
    final chapter = pdfChapterTitleForPage(_toc, _page);
    final headerText = switch (_preferences.headerContent) {
      'progress' => '${(progress * 100).round()}%',
      'chapter' => chapter ?? widget.book.title,
      _ => widget.book.title,
    };
    final footerText = switch (_preferences.footerContent) {
      'progress' => '${(progress * 100).round()}%',
      'chapter' => chapter ?? '$_page / $_pageCount',
      'time' => _pdfReaderClock(),
      _ => '$_page / $_pageCount',
    };
    return Scaffold(
      appBar: _controlsVisible && _preferences.showHeader
          ? AppBar(
              leading: Hero(
                tag: 'book-cover-${widget.book.id}',
                child: const Material(
                  color: Colors.transparent,
                  child: BackButton(),
                ),
              ),
              title: Text(headerText),
              actions: [
                IconButton(
                  tooltip: strings.text('后退到上次位置'),
                  onPressed: _history.canGoBack
                      ? () {
                          final page = _history.back();
                          if (page != null) unawaited(_goToPage(page));
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: strings.text('前进到下个位置'),
                  onPressed: _history.canGoForward
                      ? () {
                          final page = _history.forward();
                          if (page != null) unawaited(_goToPage(page));
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: strings.text('朗读'),
                  onPressed: _pageCount < 1 ? null : _showTts,
                  icon: const Icon(Icons.volume_up_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: strings.text('AI 阅读助手'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onSelected: _openAi,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'chat',
                      child: Text(strings.text('基于全文对话')),
                    ),
                    PopupMenuItem(
                      value: 'translate',
                      child: Text(strings.text('全文翻译')),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: strings.text('书内搜索'),
                  onPressed: _pageCount < 1 ? null : _showSearch,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: strings.text('阅读设置'),
                  onPressed: _prepared ? _showReadingSettings : null,
                  icon: const Icon(Icons.tune),
                ),
                IconButton(
                  tooltip: strings.text('添加书签'),
                  onPressed: _pageCount < 1 ? null : _addBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: strings.text('目录'),
                  onPressed: _toc.isEmpty ? null : _showTableOfContents,
                  icon: const Icon(Icons.toc),
                ),
              ],
            )
          : null,
      body: MouseRegion(
        onHover: (_) {
          if (!_controlsVisible) setState(() => _controlsVisible = true);
        },
        child: Listener(
          onPointerSignal: _handlePointerSignal,
          onPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              unawaited(_showReaderContextMenu(event.position));
            }
          },
          child: Stack(
            key: _bodyKey,
            children: [
              if (_error case final error?)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('${strings.text('无法打开书籍')}：$error'),
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
                      margin: 12,
                      backgroundColor: Theme.of(
                        context,
                      ).scaffoldBackgroundColor,
                      layoutPages: _preferences.flow == 'scrolled'
                          ? null
                          : _layoutPdfPagesHorizontally,
                      panAxis: _preferences.flow == 'scrolled'
                          ? PanAxis.vertical
                          : PanAxis.horizontal,
                      pageAnchor: PdfPageAnchor.all,
                      pageAnchorEnd: PdfPageAnchor.all,
                      pageDropShadow: null,
                      sizeDelegateProvider:
                          const PdfViewerSizeDelegateProviderLegacy(
                            minScale: 0.1,
                            useAlternativeFitScaleAsMinScale: false,
                            calculateInitialZoom: _fitInitialPdfPage,
                          ),
                      onViewerReady: _onViewerReady,
                      onPageChanged: _onPageChanged,
                      pagePaintCallbacks: [
                        _textSearcher.pageTextMatchPaintCallback,
                      ],
                      textSelectionParams: PdfTextSelectionParams(
                        onTextSelectionChange: (selection) =>
                            unawaited(_onTextSelectionChange(selection)),
                      ),
                    ),
                  ),
                ),
              if (_pageCount > 0 && _preferences.flow == 'paginated') ...[
                _buildCurlGestureZone(Alignment.centerLeft),
                _buildCurlGestureZone(Alignment.centerRight),
              ],
              if (_pageCount > 0 && _controlsVisible && _preferences.showFooter)
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
                            tooltip: strings.text('上一页'),
                            onPressed: _page <= 1 || _preparingTurn
                                ? null
                                : () => _prepareTurn(_page - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              footerText,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            tooltip: strings.text('下一页'),
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
              if (_searchActive)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(24),
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_textSearcher.isSearching)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: strings.text('上一个结果'),
                            onPressed: _textSearcher.matches.isEmpty
                                ? null
                                : () => _textSearcher.goToPrevMatch(),
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          Text(
                            _textSearcher.matches.isEmpty
                                ? strings.text(
                                    _textSearcher.isSearching ? '搜索中' : '无结果',
                                  )
                                : '${(_textSearcher.currentIndex ?? 0) + 1} / ${_textSearcher.matches.length}',
                          ),
                          IconButton(
                            tooltip: strings.text('下一个结果'),
                            onPressed: _textSearcher.matches.isEmpty
                                ? null
                                : () => _textSearcher.goToNextMatch(),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          IconButton(
                            tooltip: strings.text('关闭搜索'),
                            onPressed: _closeSearch,
                            icon: const Icon(Icons.close),
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
                      trailing: Wrap(
                        children: [
                          PopupMenuButton<String>(
                            tooltip: strings.text('更多选中文本操作'),
                            onSelected: (action) =>
                                unawaited(_handleSelectionAction(action)),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'copy',
                                child: Text(strings.text('复制')),
                              ),
                              PopupMenuItem(
                                value: 'web',
                                child: Text(strings.text('Web 搜索')),
                              ),
                              PopupMenuItem(
                                value: 'ai',
                                child: Text(strings.text('发送给 AI')),
                              ),
                              PopupMenuItem(
                                value: 'card',
                                child: Text(strings.text('生成分享卡片')),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: strings.text('从选中内容朗读'),
                            onPressed: _showTts,
                            icon: const Icon(Icons.volume_up_outlined),
                          ),
                          IconButton(
                            tooltip: strings.text('AI 上下文翻译'),
                            onPressed: _translateSelection,
                            icon: const Icon(Icons.translate),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _saveExcerpt,
                            icon: const Icon(Icons.format_quote),
                            label: Text(strings.text('摘录')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_ttsController.currentSentence case final sentence?
                  when _ttsController.isPlaying)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: _selection == null ? 88 : 176,
                  child: Semantics(
                    liveRegion: true,
                    label: '${strings.text('正在朗读')}：$sentence',
                    child: Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          sentence,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
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
        ),
      ),
    );
  }

  Widget _buildCurlGestureZone(Alignment alignment) => Positioned(
    top: 0,
    bottom: 0,
    left: alignment == Alignment.centerLeft ? 0 : null,
    right: alignment == Alignment.centerRight ? 0 : null,
    width: MediaQuery.sizeOf(context).width * _preferences.tapZoneRatio,
    child: Semantics(
      button: true,
      label: AppStrings.of(context).text(
        (_preferences.swapTapZones
                ? alignment == Alignment.centerLeft
                : alignment == Alignment.centerRight)
            ? '下一页'
            : '上一页',
      ),
      onTap: () {
        final isLeft = alignment == Alignment.centerLeft;
        final forward = _preferences.swapTapZones ? isLeft : !isLeft;
        unawaited(_prepareTurn(_page + (forward ? 1 : -1)));
      },
      child: Listener(
        key: Key(
          alignment == Alignment.centerLeft
              ? 'pdf-curl-left-zone'
              : 'pdf-curl-right-zone',
        ),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: const SizedBox.expand(),
      ),
    ),
  );
}

String _pdfReaderClock() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

double _fitInitialPdfPage(
  PdfDocument document,
  PdfViewerController controller,
  double fitZoom,
  double coverZoom,
) => fitZoom;

PdfPageLayout _layoutPdfPagesHorizontally(
  List<PdfPage> pages,
  PdfViewerParams params,
) {
  final height =
      pages.fold(0.0, (maximum, page) => math.max(maximum, page.height)) +
      params.margin * 2;
  final pageLayouts = <Rect>[];
  var x = params.margin;
  for (final page in pages) {
    pageLayouts.add(
      Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height),
    );
    x += page.width + params.margin * 2;
  }
  return PdfPageLayout(pageLayouts: pageLayouts, documentSize: Size(x, height));
}

int parsePdfPageLocator(String? locator) {
  if (locator == null || !locator.startsWith('pdf:')) return 1;
  final page = int.tryParse(locator.substring(4).split(':').first);
  return page == null || page < 1 ? 1 : page;
}

String pdfPageLocator(int page) => 'pdf:$page';

class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.dest,
    required this.depth,
  });

  final String title;
  final PdfDest dest;
  final int depth;
}

String? pdfChapterTitleForPage(List<PdfOutlineEntry> entries, int page) {
  PdfOutlineEntry? current;
  for (final entry in entries) {
    if (entry.dest.pageNumber <= page &&
        (current == null || entry.dest.pageNumber >= current.dest.pageNumber)) {
      current = entry;
    }
  }
  return current?.title;
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
