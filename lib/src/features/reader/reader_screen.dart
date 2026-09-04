import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/ai/translation_sheet.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/pdf_reader_screen.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/features/reader/reader_page_turn_policy.dart';
import 'package:leeef_reader/src/features/ai/ai_assistant_screen.dart';
import 'package:leeef_reader/src/features/notes/excerpt_share_card_screen.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_screen.dart';
import 'package:leeef_reader/src/page_curl/foliate_page_snapshot_view.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
import 'package:leeef_reader/src/page_curl/page_snapshot_cache.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/reader/foliate_reader_engine.dart';
import 'package:leeef_reader/src/reader/foliate_reader_view.dart';
import 'package:leeef_reader/src/reader/chinese_text_converter.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';
import 'package:leeef_reader/src/tts/configured_tts_engine.dart';
import 'package:leeef_reader/src/tts/tts_controls_sheet.dart';
import 'package:leeef_reader/src/tts/tts_media_controls.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({required this.book, super.key});

  final BookRecord book;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return switch (book.mediaType) {
      'application/epub+zip' ||
      'application/x-mobipocket-ebook' ||
      'application/vnd.amazon.ebook' ||
      'application/x-fictionbook+xml' => EpubReaderScreen(book: book),
      'application/pdf' => PdfReaderScreen(book: book),
      'text/plain' => TxtReaderScreen(book: book),
      _ => Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: Center(
          child: Text('${strings.text('暂不支持此格式')}：${book.mediaType}'),
        ),
      ),
    };
  }
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
  Timer? _clockTimer;
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
  ReaderPreferences _preferences = const ReaderPreferences();
  late final Future<ReaderPreferences> _preferencesFuture;
  int _themeRevision = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  final ChineseTextConverter _chineseConverter = const ChineseTextConverter();
  DateTime? _lastWheelTurn;
  LibraryRepository? _repository;
  DateTime? _sessionStartedAt;
  Brightness? _lastBrightness;
  late final SystemTtsController _ttsController = SystemTtsController(
    engine: ConfiguredTtsEngine(),
    mediaControls: TtsMediaControlBridge.instance,
  );

  bool get _supportsPageCurl =>
      widget.book.mediaType == 'application/epub+zip' &&
      _preferences.flow == 'paginated' &&
      effectivePageTurnEffect(
            flow: _preferences.flow,
            configuredEffect: _preferences.pageTurnEffect,
          ) ==
          'curl';

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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _preferencesFuture = ReaderPreferences.load();
    unawaited(_ttsController.initialize());
    _ttsController.addListener(_followTts);
    _eventSubscription = _engine.events.listen(_handleReaderEvent);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          (_preferences.headerContent == 'time' ||
              _preferences.footerContent == 'time')) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final changed = _lastBrightness != null && _lastBrightness != brightness;
    _lastBrightness = brightness;
    if (changed && _bookInfo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_applyPreferences(_preferences, persist: false));
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    unawaited(_persistProgress());
    unawaited(_eventSubscription?.cancel());
    unawaited(_engine.close());
    _curlTurn?.dispose();
    _snapshotCache.clear();
    _recordReadingSession();
    _ttsController.dispose();
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _followTts() {
    if (_bookInfo == null) return;
    unawaited(
      _engine.highlightTtsSentence(
        _ttsController.isPlaying ? _ttsController.currentSentence : null,
      ),
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _bookInfo == null) return false;
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
      unawaited(_engine.next());
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeUp) {
      unawaited(_prepareTurn(false));
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeDown) {
      unawaited(_prepareTurn(true));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      unawaited(_engine.previous());
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _controlsVisible = !_controlsVisible);
      return true;
    }
    return false;
  }

  void _recordReadingSession() {
    final repository = _repository;
    final startedAt = _sessionStartedAt;
    if (repository == null || startedAt == null) return;
    unawaited(
      repository.recordReadingSession(
        bookId: widget.book.id,
        startedAt: startedAt,
        endedAt: DateTime.now(),
      ),
    );
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
      _repository = repository;
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
      final preferences = await _preferencesFuture;
      final appPreferences = await SharedPreferences.getInstance();
      await _engine.setBookJavaScriptEnabled(
        appPreferences.getBool('leeef.reader.epub_javascript') ?? false,
      );
      _preferences = preferences;
      await _applyPreferences(preferences, persist: false);
      await repository.updateBookMetadata(
        bookId: widget.book.id,
        title: info.title.isEmpty ? widget.book.title : info.title,
        author: info.author,
        description: widget.book.description,
      );
      if (mounted) setState(() => _bookInfo = info);
      _sessionStartedAt ??= DateTime.now();
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_prefetchAdjacentTextures());
          unawaited(_refreshHistoryState());
          unawaited(_applyChineseConversion());
        });
      case ReaderSelectionChanged():
        setState(() {
          _selection = event;
          _controlsVisible = true;
        });
      case ReaderSelectionCleared():
        if (_selection != null) setState(() => _selection = null);
      case ReaderExternalLinkActivated():
        unawaited(_confirmExternalLink(event.href));
      case ReaderImageActivated():
        unawaited(_showImage(event));
      case ReaderFootnoteActivated():
        unawaited(_showFootnote(event));
      case ReaderFailure():
        setState(() => _error = StateError(event.message));
    }
  }

  Future<void> _refreshHistoryState() async {
    try {
      final state = await _engine.historyState();
      if (mounted) {
        setState(() {
          _canGoBack = state.canGoBack;
          _canGoForward = state.canGoForward;
        });
      }
    } on Object {
      // History is a convenience control and must not interrupt reading.
    }
  }

  Future<void> _confirmExternalLink(String href) async {
    final uri = Uri.tryParse(href);
    if (!mounted || uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      return;
    }
    final strings = AppStrings.of(context);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('打开外部链接？')),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.text('打开')),
          ),
        ],
      ),
    );
    if (approved == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showImage(ReaderImageActivated event) async {
    if (!mounted) return;
    final strings = AppStrings.of(context);
    final image = event.source.startsWith('data:')
        ? Image.memory(
            base64Decode(event.source.substring(event.source.indexOf(',') + 1)),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 72),
          )
        : Image.network(
            event.source,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 72),
          );
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              event.description?.trim().isNotEmpty == true
                  ? event.description!
                  : strings.text('图片'),
            ),
            leading: const CloseButton(),
          ),
          body: InteractiveViewer(
            minScale: .5,
            maxScale: 8,
            child: Center(child: image),
          ),
        ),
      ),
    );
  }

  Future<void> _showFootnote(ReaderFootnoteActivated event) {
    final strings = AppStrings.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(child: SelectableText(event.text)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.text('关闭')),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCurrentChapter() async {
    final text = await _engine.currentText();
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('当前章节正文已复制'))));
    }
  }

  Future<void> _copySelection() async {
    final quote = _selection?.quote;
    if (quote == null) return;
    await Clipboard.setData(ClipboardData(text: quote));
    if (mounted) {
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('已复制选中文本'))));
    }
  }

  Future<void> _searchSelectionOnWeb() async {
    final quote = _selection?.quote.trim();
    if (quote == null || quote.isEmpty) return;
    await launchUrl(
      Uri.https('www.google.com', '/search', {'q': quote}),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _sendSelectionToAi() async {
    final selection = _selection;
    if (selection == null) return;
    final contextText = await _engine.currentText();
    if (!mounted) return;
    final strings = AppStrings.of(context);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AiAssistantScreen(
          title: '${widget.book.title} · ${strings.text('选中文本')}',
          contextText: '选中文本：${selection.quote}\n\n章节上下文：$contextText',
        ),
      ),
    );
  }

  Future<void> _shareSelectionCard() async {
    final quote = _selection?.quote;
    if (quote == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ExcerptShareCardScreen(quote: quote, book: widget.book),
      ),
    );
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
    final note = await showExcerptDialog(context, quote: selection.quote);
    if (note == null || !mounted) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.createExcerpt(
      bookId: widget.book.id,
      locator: selection.cfi,
      quote: selection.quote,
      note: note.trim().isEmpty ? null : note.trim(),
    );
    if (mounted) {
      final strings = AppStrings.of(context);
      setState(() => _selection = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('书摘已保存'))));
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
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('书签已添加'))));
    }
  }

  Future<void> _showTableOfContents() async {
    final info = _bookInfo;
    if (info == null) return;
    final strings = AppStrings.of(context);
    final locator = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(strings.text('目录'))),
            ..._tocTiles(info.toc),
          ],
        ),
      ),
    );
    if (locator != null) await _engine.goTo(locator);
  }

  Iterable<Widget> _tocTiles(List<ReaderTocItem> items, [int depth = 0]) sync* {
    for (final item in items) {
      yield ListTile(
        contentPadding: EdgeInsetsDirectional.only(
          start: 16 + depth * 20,
          end: 16,
        ),
        title: Text(item.label),
        onTap: () => Navigator.pop(context, item.href),
      );
      yield* _tocTiles(item.children, depth + 1);
    }
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
          decoration: InputDecoration(
            labelText: strings.text('关键词'),
            prefixIcon: const Icon(Icons.search),
          ),
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
    if (query == null || query.isEmpty || !mounted) return;
    try {
      final results = await _engine.search(query);
      if (!mounted) return;
      final locator = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: results.isEmpty
              ? SizedBox(
                  height: 180,
                  child: Center(child: Text(strings.text('没有找到匹配内容'))),
                )
              : ListView(
                  children: [
                    ListTile(
                      title: Text(strings.searchResults(query, results.length)),
                    ),
                    for (final result in results)
                      ListTile(
                        title: Text(
                          result.label.isEmpty
                              ? strings.text('正文')
                              : result.label,
                        ),
                        subtitle: Text(
                          result.excerpt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, result.cfi),
                      ),
                  ],
                ),
        ),
      );
      if (locator != null) await _engine.goTo(locator);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${strings.text('搜索失败')}：$error')));
    }
  }

  Future<void> _showTts() async {
    final text = _selection?.quote ?? await _engine.currentText();
    if (!mounted) return;
    await showTtsControlsSheet(context, controller: _ttsController, text: text);
  }

  Future<void> _translateSelection() async {
    final selection = _selection;
    if (selection == null) return;
    final contextText = await _engine.currentText();
    if (!mounted) return;
    await showTranslationSheet(
      context,
      text: selection.quote,
      contextText: contextText,
    );
  }

  Future<void> _openAi(String action) async {
    final text = action == 'chat'
        ? await _engine.currentText()
        : await _engine.bookText();
    if (!mounted || text.trim().isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => action == 'translate'
            ? FullTranslationScreen(title: widget.book.title, sourceText: text)
            : AiAssistantScreen(
                title: '${widget.book.title} · AI',
                contextText: text,
              ),
      ),
    );
  }

  Future<void> _applyPreferences(
    ReaderPreferences preferences, {
    bool persist = true,
  }) async {
    final brightness = Theme.of(context).brightness;
    await _engine.setLayout(
      flow: preferences.flow,
      maxColumnCount: preferences.columns,
      margin: preferences.margin,
      pageTurnEffect:
          effectivePageTurnEffect(
                flow: preferences.flow,
                configuredEffect: preferences.pageTurnEffect,
              ) ==
              'none'
          ? 'none'
          : 'slide',
    );
    await _engine.setTheme(
      foreground: preferences.foreground,
      background: preferences.background,
      fontSize: preferences.fontSize,
      lineHeight: preferences.lineHeight,
      fontFamily: preferences.fontFamily,
      fontWeight: preferences.fontWeight,
      headingScale: preferences.headingScale,
      letterSpacing: preferences.letterSpacing,
      paragraphSpacing: preferences.paragraphSpacing,
      textIndent: preferences.textIndent,
      textAlign: preferences.textAlign,
      writingMode: preferences.writingMode,
      preserveBookStyles: preferences.preserveBookStyles,
      eInkMode: preferences.eInkMode,
      codeHighlight: preferences.codeHighlight,
      backgroundImage:
          brightness == Brightness.dark &&
              preferences.darkBackgroundImage.isNotEmpty
          ? preferences.darkBackgroundImage
          : preferences.backgroundImage,
      backgroundOpacity: preferences.backgroundOpacity,
      backgroundBlur: preferences.backgroundBlur,
      backgroundFit: preferences.backgroundFit,
      importedFontName: preferences.importedFontName,
      importedFontData: preferences.importedFontData,
      customCss: preferences.customCss,
    );
    await _applyReadingState(preferences);
    await _applyChineseConversion(preferences.chineseConversion);
    if (persist) await preferences.save();
    _snapshotCache.clear();
    if (mounted) {
      setState(() {
        _preferences = preferences;
        _themeRevision++;
      });
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

  Future<void> _applyChineseConversion([String? mode]) async {
    if (_bookInfo == null) return;
    try {
      final nodes = await _engine.visibleTextNodes();
      final converted = _chineseConverter.convertAll(
        nodes,
        mode ?? _preferences.chineseConversion,
      );
      await _engine.applyVisibleTextNodes(converted);
    } on Object {
      // A relocation may replace the WebView document while conversion runs.
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_preferences.mouseWheelPaging || event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (_lastWheelTurn != null &&
        now.difference(_lastWheelTurn!) < const Duration(milliseconds: 220)) {
      return;
    }
    if (event.scrollDelta.dy.abs() < 2) return;
    _lastWheelTurn = now;
    unawaited(_prepareTurn(event.scrollDelta.dy > 0));
  }

  void _handleHover(PointerHoverEvent event) {
    final height = _bodyKey.currentContext?.size?.height ?? 0;
    if (height <= 0) return;
    final position = _bodyPosition(event.position);
    final shouldShow =
        position != null && (position.dy < 64 || position.dy > height - 84);
    if (shouldShow && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
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
        unawaited(_prepareTurn(false));
      case 'next':
        unawaited(_prepareTurn(true));
      case 'search':
        unawaited(_showSearch());
      case 'settings':
        unawaited(_showReadingSettings());
      case 'bookmark':
        unawaited(_addBookmark());
    }
  }

  Future<void> _showReadingSettings() async {
    final strings = AppStrings.of(context);
    var draft = _preferences;
    final customCssController = TextEditingController(text: draft.customCss);
    final result = await showModalBottomSheet<ReaderPreferences>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('阅读样式'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'paginated',
                      label: Text(strings.text('分页')),
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
                if (draft.flow == 'paginated') ...[
                  const SizedBox(height: 8),
                  if (usesDesktopClickSlide(flow: draft.flow))
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'slide',
                          label: Text(strings.text('滑动')),
                        ),
                      ],
                      selected: const {'slide'},
                      onSelectionChanged: null,
                    )
                  else
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'curl',
                          label: Text(strings.text('仿真')),
                        ),
                        ButtonSegment(
                          value: 'slide',
                          label: Text(strings.text('滑动')),
                        ),
                        ButtonSegment(
                          value: 'none',
                          label: Text(strings.text('无动画')),
                        ),
                      ],
                      selected: {draft.pageTurnEffect},
                      onSelectionChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(
                          pageTurnEffect: value.single,
                        ),
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.text('双栏')),
                    value: draft.columns == 2,
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(columns: value ? 2 : 1),
                    ),
                  ),
                ],
                _PreferenceSlider(
                  label: strings.text('字号'),
                  value: draft.fontSize,
                  min: 12,
                  max: 32,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(fontSize: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('行距'),
                  value: draft.lineHeight,
                  min: 1.1,
                  max: 2.5,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(lineHeight: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('边距'),
                  value: draft.margin,
                  min: 0,
                  max: 72,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(margin: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('字距'),
                  value: draft.letterSpacing,
                  min: -1,
                  max: 4,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(letterSpacing: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('段距'),
                  value: draft.paragraphSpacing,
                  min: 0,
                  max: 2,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(paragraphSpacing: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('缩进'),
                  value: draft.textIndent,
                  min: 0,
                  max: 4,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(textIndent: value),
                  ),
                ),
                _PreferenceSlider(
                  label: strings.text('标题'),
                  value: draft.headingScale,
                  min: 1,
                  max: 1.8,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(headingScale: value),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.fontFamily,
                  decoration: InputDecoration(labelText: strings.text('字体')),
                  items: [
                    DropdownMenuItem(
                      value: 'serif',
                      child: Text(strings.text('衬线字体')),
                    ),
                    DropdownMenuItem(
                      value: 'sans-serif',
                      child: Text(strings.text('无衬线字体')),
                    ),
                    DropdownMenuItem(
                      value: 'monospace',
                      child: Text(strings.text('等宽字体')),
                    ),
                    DropdownMenuItem(
                      value: 'system-ui',
                      child: Text(strings.text('系统字体')),
                    ),
                    DropdownMenuItem(
                      value: 'LeeefImportedFont',
                      child: Text(strings.text('导入字体')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(fontFamily: value),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.font_download_outlined),
                  title: Text(
                    draft.importedFontName.isEmpty
                        ? strings.text('导入字体文件')
                        : '${strings.text('导入字体 · ')}${draft.importedFontName}',
                  ),
                  subtitle: Text(strings.text('支持 TTF、OTF、WOFF、WOFF2')),
                  trailing: const Icon(Icons.file_open),
                  onTap: () async {
                    final picked = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['ttf', 'otf', 'woff', 'woff2'],
                    );
                    final file = picked.singleOrNull;
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    final extension = file.name.split('.').last.toLowerCase();
                    final mime = switch (extension) {
                      'otf' => 'font/otf',
                      'woff' => 'font/woff',
                      'woff2' => 'font/woff2',
                      _ => 'font/ttf',
                    };
                    setDialogState(
                      () => draft = draft.copyWith(
                        fontFamily: 'LeeefImportedFont',
                        importedFontName: file.name,
                        importedFontData:
                            'data:$mime;base64,${base64Encode(bytes)}',
                      ),
                    );
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.textAlign,
                  decoration: InputDecoration(labelText: strings.text('文本对齐')),
                  items: [
                    DropdownMenuItem(
                      value: 'start',
                      child: Text(strings.text('原文')),
                    ),
                    DropdownMenuItem(
                      value: 'left',
                      child: Text(strings.text('左对齐')),
                    ),
                    DropdownMenuItem(
                      value: 'justify',
                      child: Text(strings.text('两端对齐')),
                    ),
                    DropdownMenuItem(
                      value: 'center',
                      child: Text(strings.text('居中')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(textAlign: value),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.writingMode,
                  decoration: InputDecoration(labelText: strings.text('排版方向')),
                  items: [
                    DropdownMenuItem(
                      value: 'horizontal-tb',
                      child: Text(strings.text('横排')),
                    ),
                    DropdownMenuItem(
                      value: 'vertical-rl',
                      child: Text(strings.text('竖排（从右到左）')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(writingMode: value),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.chineseConversion,
                  decoration: InputDecoration(labelText: strings.text('中文显示')),
                  items: [
                    DropdownMenuItem(
                      value: 'original',
                      child: Text(strings.text('保持原文')),
                    ),
                    DropdownMenuItem(
                      value: 'simplified',
                      child: Text(strings.text('转为简体')),
                    ),
                    DropdownMenuItem(
                      value: 'traditional',
                      child: Text(strings.text('转为繁体')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(chineseConversion: value),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final theme in const [
                      ('纸张', '#292b29', '#fbf8f1'),
                      ('夜间', '#d8d8d8', '#151515'),
                      ('护眼', '#26352b', '#dce8d5'),
                      ('OLED', '#eeeeee', '#000000'),
                    ])
                      ChoiceChip(
                        label: Text(strings.text(theme.$1)),
                        selected: draft.background == theme.$3,
                        onSelected: (_) => setDialogState(
                          () => draft = draft.copyWith(
                            foreground: theme.$2,
                            background: theme.$3,
                          ),
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('保留书籍原始 CSS')),
                  subtitle: Text(strings.text('关闭后统一覆盖正文排版')),
                  value: draft.preserveBookStyles,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(preserveBookStyles: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('电子墨水屏模式')),
                  subtitle: Text(strings.text('灰阶、高对比度并减少视觉效果')),
                  value: draft.eInkMode,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(eInkMode: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('代码语法配色')),
                  value: draft.codeHighlight,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(codeHighlight: value),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: Text(
                    strings.text(
                      draft.backgroundImage.isEmpty ? '选择日间背景图' : '已设置日间背景图',
                    ),
                  ),
                  trailing: draft.backgroundImage.isEmpty
                      ? const Icon(Icons.file_open)
                      : IconButton(
                          tooltip: strings.text('移除背景图'),
                          onPressed: () => setDialogState(
                            () => draft = draft.copyWith(backgroundImage: ''),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                  onTap: () async {
                    final picked = await FilePicker.pickFiles(
                      type: FileType.image,
                    );
                    final file = picked.singleOrNull;
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    final extension = file.name.split('.').last.toLowerCase();
                    final mime = extension == 'jpg' || extension == 'jpeg'
                        ? 'image/jpeg'
                        : 'image/$extension';
                    setDialogState(
                      () => draft = draft.copyWith(
                        backgroundImage:
                            'data:$mime;base64,${base64Encode(bytes)}',
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(
                    strings.text(
                      draft.darkBackgroundImage.isEmpty
                          ? '选择夜间背景图'
                          : '已设置夜间背景图',
                    ),
                  ),
                  trailing: draft.darkBackgroundImage.isEmpty
                      ? const Icon(Icons.file_open)
                      : IconButton(
                          tooltip: strings.text('移除夜间背景图'),
                          onPressed: () => setDialogState(
                            () =>
                                draft = draft.copyWith(darkBackgroundImage: ''),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                  onTap: () async {
                    final picked = await FilePicker.pickFiles(
                      type: FileType.image,
                    );
                    final file = picked.singleOrNull;
                    if (file == null) return;
                    final bytes = await file.readAsBytes();
                    final extension = file.name.split('.').last.toLowerCase();
                    final mime = extension == 'jpg' || extension == 'jpeg'
                        ? 'image/jpeg'
                        : 'image/$extension';
                    setDialogState(
                      () => draft = draft.copyWith(
                        darkBackgroundImage:
                            'data:$mime;base64,${base64Encode(bytes)}',
                      ),
                    );
                  },
                ),
                if (draft.backgroundImage.isNotEmpty ||
                    draft.darkBackgroundImage.isNotEmpty) ...[
                  _PreferenceSlider(
                    label: strings.text('透明'),
                    value: draft.backgroundOpacity,
                    min: 0,
                    max: 1,
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(backgroundOpacity: value),
                    ),
                  ),
                  _PreferenceSlider(
                    label: strings.text('模糊'),
                    value: draft.backgroundBlur,
                    min: 0,
                    max: 24,
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(backgroundBlur: value),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: draft.backgroundFit,
                    decoration: InputDecoration(
                      labelText: strings.text('背景填充'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'cover',
                        child: Text(strings.text('裁切填满')),
                      ),
                      DropdownMenuItem(
                        value: 'contain',
                        child: Text(strings.text('完整显示')),
                      ),
                      DropdownMenuItem(
                        value: '100% 100%',
                        child: Text(strings.text('拉伸填满')),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(backgroundFit: value),
                    ),
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.text('阅读交互与状态')),
                  children: [
                    _PreferenceSlider(
                      label: strings.text('点击翻页区域'),
                      value: draft.tapZoneRatio * 100,
                      min: 15,
                      max: 45,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(tapZoneRatio: value / 100),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('左右点击区域互换')),
                      value: draft.swapTapZones,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(swapTapZones: value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('音量键翻页')),
                      value: draft.volumeKeyPaging,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(volumeKeyPaging: value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('鼠标滚轮翻页')),
                      value: draft.mouseWheelPaging,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(mouseWheelPaging: value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('阅读时屏幕常亮')),
                      value: draft.keepAwake,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(keepAwake: value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('沉浸全屏')),
                      value: draft.fullscreen,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(fullscreen: value),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('显示页眉')),
                      value: draft.showHeader,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(showHeader: value ?? true),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.text('显示页脚')),
                      value: draft.showFooter,
                      onChanged: (value) => setDialogState(
                        () => draft = draft.copyWith(showFooter: value ?? true),
                      ),
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
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.text('自定义 CSS')),
                  children: [
                    TextField(
                      controller: customCssController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'p { text-indent: 2em; }',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final css = customCssController.text;
                      if (!_looksLikeValidCss(css)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.text('自定义 CSS 的大括号不匹配')),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, draft.copyWith(customCss: css));
                    },
                    child: Text(strings.text('应用')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    customCssController.dispose();
    if (result != null) await _applyPreferences(result);
  }

  static bool _looksLikeValidCss(String css) {
    if (css.contains('</style')) return false;
    var depth = 0;
    for (final unit in css.codeUnits) {
      if (unit == 123) depth++;
      if (unit == 125 && --depth < 0) return false;
    }
    return depth == 0;
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
        themeRevision: _themeRevision,
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
      if (Platform.isAndroid || Platform.isIOS) {
        unawaited(HapticFeedback.selectionClick());
      }
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
      themeRevision: _themeRevision,
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
    var direction = position.dx >= size.width * (1 - _preferences.tapZoneRatio)
        ? 1.0
        : position.dx <= size.width * _preferences.tapZoneRatio
        ? -1.0
        : 0.0;
    if (_preferences.swapTapZones) direction = -direction;
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
    final strings = AppStrings.of(context);
    final progress = _location?.progress ?? 0;
    final chapter = _location?.chapterTitle;
    final headerText = switch (_preferences.headerContent) {
      'chapter' => chapter ?? _bookInfo?.title ?? widget.book.title,
      'progress' => '${(progress * 100).round()}%',
      _ => _bookInfo?.title ?? widget.book.title,
    };
    final footerText = switch (_preferences.footerContent) {
      'page' =>
        _location?.page == null
            ? '${(progress * 100).round()}%'
            : strings.pageNumber(_location!.page!),
      'chapter' => chapter ?? '${(progress * 100).round()}%',
      'time' => _readerClock(),
      _ => '${(progress * 100).round()}%',
    };
    final bookSource = _bookSource;
    final compactToolbar = MediaQuery.sizeOf(context).width < 600;
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
                if (!compactToolbar) ...[
                  IconButton(
                    tooltip: strings.text('后退到上次跳转位置'),
                    onPressed: _canGoBack ? _engine.historyBack : null,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: strings.text('前进到下个跳转位置'),
                    onPressed: _canGoForward ? _engine.historyForward : null,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
                if (!Platform.isIOS)
                  IconButton(
                    tooltip: strings.text('朗读'),
                    onPressed: _bookInfo == null ? null : _showTts,
                    icon: const Icon(Icons.volume_up_outlined),
                  ),
                PopupMenuButton<String>(
                  tooltip: strings.text('AI 阅读助手'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  onSelected: _openAi,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'chat',
                      child: Text(strings.text('基于当前章节对话')),
                    ),
                    PopupMenuItem(
                      value: 'full-summary',
                      child: Text(strings.text('基于全书对话与总结')),
                    ),
                    PopupMenuItem(
                      value: 'translate',
                      child: Text(strings.text('全文翻译')),
                    ),
                  ],
                ),
                if (!compactToolbar) ...[
                  IconButton(
                    tooltip: strings.text('书内搜索'),
                    onPressed: _bookInfo == null ? null : _showSearch,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: strings.text('阅读样式'),
                    onPressed: _bookInfo == null ? null : _showReadingSettings,
                    icon: const Icon(Icons.text_fields),
                  ),
                  IconButton(
                    tooltip: strings.text('添加书签'),
                    onPressed: _location == null ? null : _addBookmark,
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                  IconButton(
                    tooltip: strings.text('目录'),
                    onPressed: _bookInfo == null ? null : _showTableOfContents,
                    icon: const Icon(Icons.toc),
                  ),
                ],
                PopupMenuButton<String>(
                  tooltip: strings.text('更多阅读操作'),
                  onSelected: (value) {
                    final action = switch (value) {
                      'search' => _showSearch,
                      'style' => _showReadingSettings,
                      'bookmark' => _addBookmark,
                      'toc' => _showTableOfContents,
                      _ => _copyCurrentChapter,
                    };
                    unawaited(action());
                  },
                  itemBuilder: (_) => [
                    if (compactToolbar) ...[
                      PopupMenuItem(
                        value: 'search',
                        enabled: _bookInfo != null,
                        child: ListTile(
                          leading: const Icon(Icons.search),
                          title: Text(strings.text('书内搜索')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'style',
                        enabled: _bookInfo != null,
                        child: ListTile(
                          leading: const Icon(Icons.text_fields),
                          title: Text(strings.text('阅读样式')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bookmark',
                        enabled: _location != null,
                        child: ListTile(
                          leading: const Icon(Icons.bookmark_add_outlined),
                          title: Text(strings.text('添加书签')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toc',
                        enabled: _bookInfo != null,
                        child: ListTile(
                          leading: const Icon(Icons.toc),
                          title: Text(strings.text('目录')),
                        ),
                      ),
                    ],
                    PopupMenuItem(
                      value: 'copy-chapter',
                      child: ListTile(
                        leading: Icon(Icons.copy_all_outlined),
                        title: Text(strings.text('复制当前章节正文')),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: MouseRegion(
        onHover: _handleHover,
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
                  onTap: () =>
                      setState(() => _controlsVisible = !_controlsVisible),
                  child: FoliateReaderView(
                    engine: _engine,
                    onWebViewCreated: (_) => unawaited(_openBook()),
                  ),
                ),
              ),
              if (_supportsPageCurl && _bookInfo != null) ...[
                _buildCurlGestureZone(Alignment.centerLeft),
                _buildCurlGestureZone(Alignment.centerRight),
              ] else if (_bookInfo != null) ...[
                _buildTapGestureZone(Alignment.centerLeft),
                _buildTapGestureZone(Alignment.centerRight),
              ],
              if (_error case final error?)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('${strings.text('无法打开书籍')}：$error'),
                      ),
                    ),
                  ),
                ),
              if (_controlsVisible && _preferences.showFooter)
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
                              tooltip: strings.text('上一页'),
                              onPressed: _bookInfo == null || _preparingTurn
                                  ? null
                                  : () => _prepareTurn(false),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            SizedBox(
                              width: 88,
                              child: Text(
                                footerText,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              tooltip: strings.text('下一页'),
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
                      trailing: Wrap(
                        children: [
                          PopupMenuButton<String>(
                            tooltip: strings.text('更多选中文本操作'),
                            onSelected: (value) => switch (value) {
                              'copy' => unawaited(_copySelection()),
                              'web' => unawaited(_searchSelectionOnWeb()),
                              'ai' => unawaited(_sendSelectionToAi()),
                              'card' => unawaited(_shareSelectionCard()),
                              _ => null,
                            },
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
                          if (!Platform.isIOS)
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
        unawaited(_prepareTurn(_preferences.swapTapZones ? isLeft : !isLeft));
      },
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
    ),
  );

  Widget _buildTapGestureZone(Alignment alignment) => Positioned(
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
      child: GestureDetector(
        key: Key(
          alignment == Alignment.centerLeft
              ? 'epub-tap-left-zone'
              : 'epub-tap-right-zone',
        ),
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final isLeft = alignment == Alignment.centerLeft;
          final forward = _preferences.swapTapZones ? isLeft : !isLeft;
          unawaited(_prepareTurn(forward));
        },
      ),
    ),
  );
}

String _readerClock() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
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

class _PreferenceSlider extends StatelessWidget {
  const _PreferenceSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 44, child: Text(value.toStringAsFixed(1))),
    ],
  );
}
