import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/ai/translation_sheet.dart';
import 'package:leeef_reader/src/features/ai/ai_assistant_screen.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/domain/reading_location.dart';
import 'package:leeef_reader/src/features/reader/reader_excerpt_dialog.dart';
import 'package:leeef_reader/src/features/notes/excerpt_share_card_screen.dart';
import 'package:leeef_reader/src/features/reader/txt_reader_document.dart';
import 'package:leeef_reader/src/features/reader/txt_page_snapshot_renderer.dart';
import 'package:leeef_reader/src/page_curl/page_curl_controller.dart';
import 'package:leeef_reader/src/page_curl/page_curl_surface.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/reader/chinese_text_converter.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';
import 'package:leeef_reader/src/reader/reader_navigation_history.dart';
import 'package:leeef_reader/src/tts/system_tts_controller.dart';
import 'package:leeef_reader/src/tts/configured_tts_engine.dart';
import 'package:leeef_reader/src/tts/tts_controls_sheet.dart';
import 'package:leeef_reader/src/tts/tts_media_controls.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  Timer? _clockTimer;
  String? _lastPersistedLocator;
  bool _preparingTurn = false;
  _TxtCurlTurn? _curlTurn;
  int? _snapshotPageIndex;
  final GlobalKey _bodyKey = GlobalKey();
  final GlobalKey _visiblePageBoundaryKey = GlobalKey();
  final GlobalKey _snapshotPageBoundaryKey = GlobalKey();
  final ScrollController _textScrollController = ScrollController();
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  PageCurlController? _pointerCurlController;
  Offset? _lastPointerPosition;
  Duration? _lastPointerTime;
  double _horizontalVelocity = 0;
  LibraryRepository? _repository;
  ReaderPreferences _preferences = const ReaderPreferences();
  final ChineseTextConverter _chineseConverter = const ChineseTextConverter();
  final Map<String, String> _convertedPageCache = {};
  final Map<String, _TxtDisplayText> _displayTextCache = {};
  bool _controlsVisible = true;
  DateTime? _lastWheelTurn;
  String? _loadedFontData;
  final ReaderNavigationHistory _history = ReaderNavigationHistory();
  DateTime? _sessionStartedAt;
  late final SystemTtsController _ttsController = SystemTtsController(
    engine: ConfiguredTtsEngine(),
    mediaControls: TtsMediaControlBridge.instance,
  );

  bool get _supportsPageCurl =>
      _preferences.flow == 'paginated' &&
      _preferences.pageTurnEffect == 'curl' &&
      (widget.pageCurlEnabled ?? (Platform.isIOS || Platform.isAndroid));

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _textScrollController.addListener(_handleTextScroll);
    unawaited(_ttsController.initialize());
    _ttsController.addListener(_followTts);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          (_preferences.headerContent == 'time' ||
              _preferences.footerContent == 'time')) {
        setState(() {});
      }
    });
    unawaited(_open());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    _curlTurn?.dispose();
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
    _textScrollController.dispose();
    unawaited(WakelockPlus.disable());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _followTts() {
    if (mounted) setState(() {});
    final sentence = _ttsController.currentSentence;
    final document = _document;
    if (!_ttsController.isPlaying || sentence == null || document == null) {
      return;
    }
    final page = _preferences.flow == 'scrolled'
        ? TxtPage(start: 0, end: document.text.length, text: document.text)
        : document.pages[_pageIndex];
    final index = page.text.indexOf(sentence);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_textScrollController.hasClients) return;
      final fraction = index / page.text.length.clamp(1, page.text.length);
      unawaited(
        _textScrollController.animateTo(
          _textScrollController.position.maxScrollExtent * fraction,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    final document = _document;
    if (event is! KeyDownEvent || document == null) return false;
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
      if (_pageIndex + 1 < document.pages.length) {
        unawaited(_prepareTurn(_pageIndex + 1));
      }
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      if (_pageIndex > 0) unawaited(_prepareTurn(_pageIndex - 1));
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeUp) {
      if (_pageIndex > 0) unawaited(_prepareTurn(_pageIndex - 1));
      return true;
    }
    if (_preferences.volumeKeyPaging &&
        key == LogicalKeyboardKey.audioVolumeDown) {
      if (_pageIndex + 1 < document.pages.length) {
        unawaited(_prepareTurn(_pageIndex + 1));
      }
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _controlsVisible = !_controlsVisible);
      return true;
    }
    return false;
  }

  Future<void> _open() async {
    try {
      final path = widget.book.filePath;
      if (path == null) throw StateError('这本书尚未下载到本机。');
      final preferences = await ReaderPreferences.load();
      await _loadImportedFont(preferences);
      await _applyReadingState(preferences);
      final document = TxtReaderDocument.decode(
        await File(path).readAsBytes(),
        chapterPattern: preferences.txtChapterPattern,
      );
      final repository = await ref.read(libraryRepositoryProvider.future);
      _repository = repository;
      final progress = await repository.getReadingProgress(widget.book.id);
      final offset = parseTxtLocator(
        progress?.locator,
      ).clamp(0, document.text.length);
      _lastPersistedLocator = progress?.locator;
      if (mounted) {
        setState(() {
          _document = document;
          _preferences = preferences;
          _sessionStartedAt ??= DateTime.now();
          _pageIndex = document.pageIndexForOffset(offset);
          _history.reset(_pageIndex);
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
      _history.visit(next);
      _selection = null;
    });
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(HapticFeedback.selectionClick());
    }
    _scheduleProgressSave();
    if (_preferences.flow == 'scrolled') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_textScrollController.hasClients) return;
        final denominator = (document.pages.length - 1).clamp(1, 1 << 30);
        unawaited(
          _textScrollController.animateTo(
            _textScrollController.position.maxScrollExtent * next / denominator,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      });
    }
  }

  void _handleTextScroll() {
    final document = _document;
    if (_preferences.flow != 'scrolled' ||
        document == null ||
        !_textScrollController.hasClients ||
        document.pages.length < 2) {
      return;
    }
    final maximum = _textScrollController.position.maxScrollExtent;
    if (maximum <= 0) return;
    final next =
        ((_textScrollController.offset / maximum) * (document.pages.length - 1))
            .round()
            .clamp(0, document.pages.length - 1);
    if (next == _pageIndex) return;
    setState(() => _pageIndex = next);
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
    final backgroundColor = _hexColor(_preferences.background);
    final textStyle = TextStyle(
      color: _hexColor(_preferences.foreground),
      fontSize: _preferences.fontSize,
      height: _preferences.lineHeight,
      fontFamily: _preferences.fontFamily == 'system-ui'
          ? null
          : _preferences.fontFamily,
      letterSpacing: _preferences.letterSpacing,
    );
    final textDirection = Directionality.of(context);

    setState(() {
      _preparingTurn = true;
      _snapshotPageIndex = target;
    });
    ui.Image? currentImage;
    ui.Image? targetImage;
    try {
      await _waitForSnapshotPagePaint();
      final images = await Future.wait([
        _captureTxtPage(
          boundaryKey: _visiblePageBoundaryKey,
          pixelRatio: pixelRatio,
          fallback: () => renderTxtPageSnapshot(
            text: document.pages[_pageIndex].text,
            size: size,
            pixelRatio: pixelRatio,
            backgroundColor: backgroundColor,
            textStyle: textStyle,
            textDirection: textDirection,
          ),
        ),
        _captureTxtPage(
          boundaryKey: _snapshotPageBoundaryKey,
          pixelRatio: pixelRatio,
          fallback: () => renderTxtPageSnapshot(
            text: document.pages[target].text,
            size: size,
            pixelRatio: pixelRatio,
            backgroundColor: backgroundColor,
            textStyle: textStyle,
            textDirection: textDirection,
          ),
        ),
      ]);
      currentImage = images[0];
      targetImage = images[1];
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
          direction: target > _pageIndex ? 1 : -1,
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
      if (mounted) {
        setState(() {
          _preparingTurn = false;
          _snapshotPageIndex = null;
        });
      }
    }
  }

  Future<void> _waitForSnapshotPagePaint() async {
    for (var frame = 0; frame < 2 && mounted; frame++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<ui.Image> _captureTxtPage({
    required GlobalKey boundaryKey,
    required double pixelRatio,
    required Future<ui.Image> Function() fallback,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
      return fallback();
    }
    if (renderObject.debugNeedsPaint) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || renderObject.debugNeedsPaint) return fallback();
    return renderObject.toImage(pixelRatio: pixelRatio);
  }

  void _handlePointerDown(PointerDownEvent event) {
    final position = _bodyPosition(event.position);
    if (position == null) return;
    _pointerDownPosition = position;
    _pointerDownAt = DateTime.now();
    _lastPointerPosition = position;
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
    final x = position.dx;
    var direction = x >= size.width * (1 - _preferences.tapZoneRatio)
        ? 1.0
        : x <= size.width * _preferences.tapZoneRatio
        ? -1.0
        : 0.0;
    if (_preferences.swapTapZones) direction = -direction;
    final target = _pageIndex + direction.toInt();
    if (direction == 0 || target < 0 || target >= document.pages.length) return;

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
    if (start == null || startedAt == null || position == null) return;
    final isTap =
        DateTime.now().difference(startedAt) <=
            const Duration(milliseconds: 350) &&
        (position - start).distance <= 12;
    if (_pointerCurlController case final controller?) {
      controller
        ..update(position)
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
    if (position.dx <= width * _preferences.tapZoneRatio) {
      unawaited(
        _prepareTurn(_pageIndex + (_preferences.swapTapZones ? 1 : -1)),
      );
    } else if (position.dx >= width * (1 - _preferences.tapZoneRatio)) {
      unawaited(
        _prepareTurn(_pageIndex + (_preferences.swapTapZones ? -1 : 1)),
      );
    }
  }

  Offset? _bodyPosition(Offset globalPosition) {
    final renderObject = _bodyKey.currentContext?.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.globalToLocal(globalPosition)
        : null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _pointerCurlController?.release(horizontalVelocity: 0);
    _pointerCurlController = null;
    _lastPointerPosition = null;
    _lastPointerTime = null;
  }

  Future<void> _finishTurn({required bool completed}) async {
    final turn = _curlTurn;
    if (turn == null) return;
    if (completed) {
      setState(() {
        _pageIndex = turn.targetIndex;
        _history.visit(turn.targetIndex);
        _selection = null;
      });
      _scheduleProgressSave();
      await _waitForTargetPagePaint();
      if (!mounted || !identical(_curlTurn, turn)) return;
    }
    setState(() => _curlTurn = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => turn.dispose());
  }

  Future<void> _waitForTargetPagePaint() async {
    for (var frame = 0; frame < 2 && mounted; frame++) {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
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
    final repository = _repository;
    if (document == null || repository == null) return;
    final page = document.pages[_pageIndex];
    final locator = txtLocator(page.start);
    if (locator == _lastPersistedLocator) return;
    await repository.updateReadingProgress(
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
    final page = _preferences.flow == 'scrolled'
        ? TxtPage(start: 0, end: document.text.length, text: document.text)
        : document.pages[_pageIndex];
    final display = _displayText(page);
    final start = display.originalOffset(selection.start);
    final end = display.originalOffset(selection.end);
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
    final strings = AppStrings.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.text('书摘已保存'))));
  }

  Future<void> _addBookmark() async {
    final document = _document;
    if (document == null) return;
    final strings = AppStrings.of(context);
    await (await ref.read(libraryRepositoryProvider.future)).createBookmark(
      bookId: widget.book.id,
      locator: txtLocator(document.pages[_pageIndex].start),
      title: strings.pageNumber(_pageIndex + 1),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('书签已添加'))));
    }
  }

  Future<void> _showTableOfContents() async {
    final document = _document;
    if (document == null || document.chapters.isEmpty) return;
    final strings = AppStrings.of(context);
    final offset = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(strings.text('目录'))),
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

  Future<void> _showSearch() async {
    final document = _document;
    if (document == null) return;
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
    if (query == null || query.isEmpty || !mounted) return;
    final haystack = document.text.toLowerCase();
    final needle = query.toLowerCase();
    final offsets = <int>[];
    var cursor = 0;
    while (offsets.length < 500) {
      final found = haystack.indexOf(needle, cursor);
      if (found < 0) break;
      offsets.add(found);
      cursor = found + needle.length;
    }
    final offset = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: offsets.isEmpty
            ? SizedBox(
                height: 180,
                child: Center(child: Text(strings.text('没有找到匹配内容'))),
              )
            : ListView(
                children: [
                  ListTile(
                    title: Text(strings.searchResults(query, offsets.length)),
                  ),
                  for (final offset in offsets)
                    ListTile(
                      title: Text(
                        _chapterAt(
                          document,
                          offset,
                          defaultLabel: strings.text('正文'),
                        ),
                      ),
                      subtitle: Text(
                        _searchExcerpt(document.text, offset, needle.length),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, offset),
                    ),
                ],
              ),
      ),
    );
    if (offset != null) _goToPage(document.pageIndexForOffset(offset));
  }

  static String _chapterAt(
    TxtReaderDocument document,
    int offset, {
    String defaultLabel = '正文',
  }) {
    var label = defaultLabel;
    for (final chapter in document.chapters) {
      if (chapter.offset > offset) break;
      label = chapter.title;
    }
    return label;
  }

  static String _searchExcerpt(String text, int offset, int length) {
    final start = (offset - 45).clamp(0, text.length);
    final end = (offset + length + 75).clamp(0, text.length);
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _showReadingSettings() async {
    final strings = AppStrings.of(context);
    var draft = _preferences;
    final chapterPatternController = TextEditingController(
      text: draft.txtChapterPattern,
    );
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
                  strings.text('阅读样式'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
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
                      () =>
                          draft = draft.copyWith(pageTurnEffect: value.single),
                    ),
                  ),
                ],
                _styleSlider(
                  label: strings.text('字号'),
                  value: draft.fontSize,
                  min: 12,
                  max: 32,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(fontSize: value),
                  ),
                ),
                _styleSlider(
                  label: strings.text('行距'),
                  value: draft.lineHeight,
                  min: 1.1,
                  max: 2.5,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(lineHeight: value),
                  ),
                ),
                _styleSlider(
                  label: strings.text('边距'),
                  value: draft.margin,
                  min: 8,
                  max: 72,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(margin: value),
                  ),
                ),
                _styleSlider(
                  label: strings.text('字重'),
                  value: draft.fontWeight.toDouble(),
                  min: 100,
                  max: 900,
                  divisions: 8,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(
                      fontWeight: (value / 100).round() * 100,
                    ),
                  ),
                ),
                _styleSlider(
                  label: strings.text('字距'),
                  value: draft.letterSpacing,
                  min: -1,
                  max: 4,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(letterSpacing: value),
                  ),
                ),
                _styleSlider(
                  label: strings.text('段距'),
                  value: draft.paragraphSpacing,
                  min: 0,
                  max: 2,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(paragraphSpacing: value),
                  ),
                ),
                _styleSlider(
                  label: strings.text('首行缩进'),
                  value: draft.textIndent,
                  min: 0,
                  max: 4,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(textIndent: value),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.fontFamily,
                  decoration: InputDecoration(labelText: strings.text('字体')),
                  items: [
                    DropdownMenuItem(
                      value: 'serif',
                      child: Text(strings.text('衬线体')),
                    ),
                    DropdownMenuItem(
                      value: 'sans-serif',
                      child: Text(strings.text('无衬线体')),
                    ),
                    DropdownMenuItem(
                      value: 'monospace',
                      child: Text(strings.text('等宽体')),
                    ),
                    DropdownMenuItem(
                      value: 'system-ui',
                      child: Text(strings.text('系统字体')),
                    ),
                    if (draft.importedFontName.isNotEmpty)
                      DropdownMenuItem(
                        value: 'LeeefImportedFont',
                        child: Text(
                          '${strings.text('导入字体 · ')}${draft.importedFontName}',
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(fontFamily: value),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: draft.textAlign,
                  decoration: InputDecoration(labelText: strings.text('文本对齐')),
                  items: [
                    DropdownMenuItem(
                      value: 'start',
                      child: Text(strings.text('起始对齐')),
                    ),
                    DropdownMenuItem(
                      value: 'left',
                      child: Text(strings.text('左对齐')),
                    ),
                    DropdownMenuItem(
                      value: 'center',
                      child: Text(strings.text('居中')),
                    ),
                    DropdownMenuItem(
                      value: 'justify',
                      child: Text(strings.text('两端对齐')),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(textAlign: value),
                  ),
                ),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.text('电子墨水屏模式')),
                  subtitle: Text(strings.text('使用灰阶高对比度并关闭背景效果')),
                  value: draft.eInkMode,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(eInkMode: value),
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
                  _styleSlider(
                    label: strings.text('透明'),
                    value: draft.backgroundOpacity,
                    min: 0,
                    max: 1,
                    onChanged: (value) => setDialogState(
                      () => draft = draft.copyWith(backgroundOpacity: value),
                    ),
                  ),
                  _styleSlider(
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
                        child: Text(strings.text('覆盖')),
                      ),
                      DropdownMenuItem(
                        value: 'contain',
                        child: Text(strings.text('完整显示')),
                      ),
                      DropdownMenuItem(
                        value: 'fill',
                        child: Text(strings.text('拉伸')),
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
                    _styleSlider(
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
                    for (final option
                        in <(String, bool, ReaderPreferences Function(bool))>[
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
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.text('TXT 章节切分规则')),
                  subtitle: Text(strings.text('留空时使用内置的中文小说与 Chapter 规则')),
                  children: [
                    TextField(
                      controller: chapterPatternController,
                      decoration: InputDecoration(
                        labelText: strings.text('章节标题正则表达式'),
                        hintText: r'^(第.+章|Chapter\s+\d+)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final pattern = chapterPatternController.text.trim();
                      try {
                        if (pattern.isNotEmpty) RegExp(pattern);
                      } on FormatException catch (error) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${strings.text('正则表达式无效')}：$error'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(
                        context,
                        draft.copyWith(txtChapterPattern: pattern),
                      );
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
    chapterPatternController.dispose();
    if (result == null) return;
    final patternChanged =
        result.txtChapterPattern != _preferences.txtChapterPattern;
    await result.save();
    await _loadImportedFont(result);
    await _applyReadingState(result);
    if (mounted) {
      final document = _document;
      final offset = document?.pages[_pageIndex].start ?? 0;
      setState(() {
        _preferences = result;
        _convertedPageCache.clear();
        _displayTextCache.clear();
        if (document != null && patternChanged) {
          _document = TxtReaderDocument.fromText(
            document.text,
            chapterPattern: result.txtChapterPattern,
          );
          _pageIndex = _document!.pageIndexForOffset(offset);
          _history.reset(_pageIndex);
        }
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

  Future<void> _loadImportedFont(ReaderPreferences preferences) async {
    final data = preferences.importedFontData;
    if (data.isEmpty || data == _loadedFontData) return;
    final bytes = _decodeDataUri(data);
    if (bytes == null || bytes.isEmpty) return;
    final loader = FontLoader('LeeefImportedFont')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFontData = data;
  }

  String _pageText(TxtPage page) => _convertedPageCache.putIfAbsent(
    '${page.start}:${page.end}',
    () => _chineseConverter.convert(page.text, _preferences.chineseConversion),
  );

  _TxtDisplayText _displayText(TxtPage page) =>
      _displayTextCache.putIfAbsent('${page.start}:${page.end}', () {
        final source = _pageText(page);
        final output = StringBuffer();
        final offsets = <int>[0];
        final indent = _preferences.textIndent.round();
        final extraBreaks = _preferences.paragraphSpacing.round();
        var sourceOffset = 0;
        for (final line in source.split('\n')) {
          if (line.trim().isNotEmpty) {
            for (var index = 0; index < indent; index++) {
              output.write('　');
              offsets.add(sourceOffset);
            }
          }
          for (var index = 0; index < line.length; index++) {
            output.writeCharCode(line.codeUnitAt(index));
            sourceOffset++;
            offsets.add(sourceOffset);
          }
          if (sourceOffset < source.length) {
            output.write('\n');
            sourceOffset++;
            offsets.add(sourceOffset);
            if (line.trim().isNotEmpty) {
              for (var index = 0; index < extraBreaks; index++) {
                output.write('\n');
                offsets.add(sourceOffset);
              }
            }
          }
        }
        return _TxtDisplayText(text: output.toString(), offsets: offsets);
      });

  void _handlePointerSignal(PointerSignalEvent event) {
    final document = _document;
    if (!_preferences.mouseWheelPaging ||
        event is! PointerScrollEvent ||
        document == null ||
        event.scrollDelta.dy.abs() < 2) {
      return;
    }
    final now = DateTime.now();
    if (_lastWheelTurn != null &&
        now.difference(_lastWheelTurn!) < const Duration(milliseconds: 220)) {
      return;
    }
    _lastWheelTurn = now;
    final target = _pageIndex + (event.scrollDelta.dy > 0 ? 1 : -1);
    if (target >= 0 && target < document.pages.length) {
      unawaited(_prepareTurn(target));
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
        if (_pageIndex > 0) unawaited(_prepareTurn(_pageIndex - 1));
      case 'next':
        if (_document != null && _pageIndex + 1 < _document!.pages.length) {
          unawaited(_prepareTurn(_pageIndex + 1));
        }
      case 'search':
        unawaited(_showSearch());
      case 'settings':
        unawaited(_showReadingSettings());
      case 'bookmark':
        unawaited(_addBookmark());
    }
  }

  Future<void> _showTts() async {
    final document = _document;
    if (document == null) return;
    await showTtsControlsSheet(
      context,
      controller: _ttsController,
      text: _selection?.quote ?? document.pages[_pageIndex].text,
    );
  }

  Future<void> _translateSelection() async {
    final document = _document;
    final selection = _selection;
    if (document == null || selection == null) return;
    await showTranslationSheet(
      context,
      text: selection.quote,
      contextText: document.pages[_pageIndex].text,
    );
  }

  Future<void> _handleSelectionAction(String action) async {
    final selection = _selection;
    final document = _document;
    if (selection == null || document == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: selection.quote));
      case 'web':
        await launchUrl(
          Uri.https('www.google.com', '/search', {'q': selection.quote}),
          mode: LaunchMode.externalApplication,
        );
      case 'ai':
        if (!mounted) return;
        final strings = AppStrings.of(context);
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AiAssistantScreen(
              title: '${widget.book.title} · ${strings.text('选中文本')}',
              contextText:
                  '选中文本：${selection.quote}\n\n页面上下文：${document.pages[_pageIndex].text}',
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
    final text = _document?.text ?? '';
    if (text.trim().isEmpty) return;
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

  Widget _styleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
      SizedBox(width: 44, child: Text(value.toStringAsFixed(1))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final document = _document;
    final page = document == null
        ? null
        : _preferences.flow == 'scrolled'
        ? TxtPage(start: 0, end: document.text.length, text: document.text)
        : document.pages[_pageIndex];
    final chapter = document == null
        ? null
        : _chapterAt(
            document,
            document.pages[_pageIndex].start,
            defaultLabel: strings.text('正文'),
          );
    final progress = document == null || document.pages.isEmpty
        ? 0.0
        : (_pageIndex + 1) / document.pages.length;
    final headerText = switch (_preferences.headerContent) {
      'chapter' => chapter ?? widget.book.title,
      'progress' => '${(progress * 100).round()}%',
      _ => widget.book.title,
    };
    final footerText = switch (_preferences.footerContent) {
      'progress' => '${(progress * 100).round()}%',
      'chapter' => chapter ?? widget.book.title,
      'time' => _txtReaderClock(),
      _ =>
        document == null ? '—' : '${_pageIndex + 1} / ${document.pages.length}',
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
                          if (page != null) _goToPage(page);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: strings.text('前进到下个位置'),
                  onPressed: _history.canGoForward
                      ? () {
                          final page = _history.forward();
                          if (page != null) _goToPage(page);
                        }
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: strings.text('朗读'),
                  onPressed: document == null ? null : _showTts,
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
                  onPressed: document == null ? null : _showSearch,
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: strings.text('阅读样式'),
                  onPressed: document == null ? null : _showReadingSettings,
                  icon: const Icon(Icons.text_fields),
                ),
                IconButton(
                  tooltip: strings.text('添加书签'),
                  onPressed: document == null ? null : _addBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: strings.text('目录'),
                  onPressed: document == null || document.chapters.isEmpty
                      ? null
                      : _showTableOfContents,
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
              else if (page == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_preferences.flow == 'paginated')
                  if (_snapshotPageIndex case final snapshotPageIndex?)
                    Positioned.fill(
                      child: ExcludeSemantics(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            key: _snapshotPageBoundaryKey,
                            child: _buildTxtPage(
                              document!.pages[snapshotPageIndex],
                              interactive: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                Positioned.fill(
                  child: RepaintBoundary(
                    key: _visiblePageBoundaryKey,
                    child: AnimatedSwitcher(
                      duration:
                          _preferences.flow == 'paginated' &&
                              _preferences.pageTurnEffect == 'slide'
                          ? const Duration(milliseconds: 220)
                          : Duration.zero,
                      transitionBuilder: (child, animation) => SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(.08, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(
                          _preferences.flow == 'scrolled'
                              ? 'continuous'
                              : _pageIndex,
                        ),
                        child: _buildTxtPage(page, interactive: true),
                      ),
                    ),
                  ),
                ),
              ],
              if (page != null && _supportsPageCurl) ...[
                _buildCurlGestureZone(Alignment.centerLeft),
                _buildCurlGestureZone(Alignment.centerRight),
              ] else if (page != null && _preferences.flow == 'paginated') ...[
                _buildTapGestureZone(Alignment.centerLeft),
                _buildTapGestureZone(Alignment.centerRight),
              ],
              if (document != null &&
                  _controlsVisible &&
                  _preferences.showFooter)
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
                            onPressed: _pageIndex == 0 || _preparingTurn
                                ? null
                                : () => _prepareTurn(_pageIndex - 1),
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
              if (_curlTurn case final turn?)
                Positioned.fill(
                  child: PageCurlSurface(
                    key: const Key('txt-page-curl'),
                    currentPage: turn.current,
                    nextPage: turn.target,
                    direction: turn.direction,
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
        final document = _document;
        if (document == null) return;
        final isLeft = alignment == Alignment.centerLeft;
        final forward = _preferences.swapTapZones ? isLeft : !isLeft;
        final target = _pageIndex + (forward ? 1 : -1);
        if (target >= 0 && target < document.pages.length) {
          unawaited(_prepareTurn(target));
        }
      },
      child: Listener(
        key: Key(
          alignment == Alignment.centerLeft
              ? 'txt-curl-left-zone'
              : 'txt-curl-right-zone',
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
              ? 'txt-tap-left-zone'
              : 'txt-tap-right-zone',
        ),
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final document = _document;
          if (document == null) return;
          final isLeft = alignment == Alignment.centerLeft;
          final forward = _preferences.swapTapZones ? isLeft : !isLeft;
          final target = _pageIndex + (forward ? 1 : -1);
          if (target >= 0 && target < document.pages.length) {
            unawaited(_prepareTurn(target));
          }
        },
      ),
    ),
  );

  Widget _buildTxtPage(TxtPage page, {required bool interactive}) {
    final background = _preferences.eInkMode
        ? Colors.white
        : _hexColor(_preferences.background);
    final foreground = _preferences.eInkMode
        ? Colors.black
        : _hexColor(_preferences.foreground);
    final selectedBackground =
        Theme.of(context).brightness == Brightness.dark &&
            _preferences.darkBackgroundImage.isNotEmpty
        ? _preferences.darkBackgroundImage
        : _preferences.backgroundImage;
    final backgroundBytes = _preferences.eInkMode
        ? null
        : _decodeDataUri(selectedBackground);
    final content = SingleChildScrollView(
      key: ValueKey(
        interactive
            ? 'txt-page-$_pageIndex'
            : 'txt-snapshot-$_snapshotPageIndex',
      ),
      primary: false,
      controller: interactive ? _textScrollController : null,
      padding: EdgeInsets.fromLTRB(
        _preferences.margin,
        24,
        _preferences.margin,
        120,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SelectableText.rich(
            _ttsTextSpan(_displayText(page).text, interactive: interactive),
            key: interactive ? const Key('txt-reader-text') : null,
            onSelectionChanged: interactive ? _onSelectionChanged : null,
            textAlign: switch (_preferences.textAlign) {
              'center' => TextAlign.center,
              'justify' => TextAlign.justify,
              'left' => TextAlign.left,
              _ => TextAlign.start,
            },
            style: TextStyle(
              color: foreground,
              fontSize: _preferences.fontSize,
              height: _preferences.lineHeight,
              fontFamily: _preferences.fontFamily == 'system-ui'
                  ? null
                  : _preferences.fontFamily,
              fontWeight: FontWeight
                  .values[(_preferences.fontWeight ~/ 100 - 1).clamp(0, 8)],
              letterSpacing: _preferences.letterSpacing,
            ),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (backgroundBytes != null)
            Opacity(
              opacity: _preferences.backgroundOpacity,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: _preferences.backgroundBlur,
                  sigmaY: _preferences.backgroundBlur,
                ),
                child: Image.memory(
                  backgroundBytes,
                  fit: _preferences.backgroundFit == 'contain'
                      ? BoxFit.contain
                      : _preferences.backgroundFit == 'fill'
                      ? BoxFit.fill
                      : BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          content,
        ],
      ),
    );
  }

  TextSpan _ttsTextSpan(String text, {required bool interactive}) {
    final rawSentence = interactive && _ttsController.isPlaying
        ? _ttsController.currentSentence
        : null;
    final sentence = rawSentence == null
        ? null
        : _chineseConverter.convert(
            rawSentence,
            _preferences.chineseConversion,
          );
    final index = sentence == null ? -1 : text.indexOf(sentence);
    final base = TextStyle(
      color: _hexColor(_preferences.foreground),
      fontSize: _preferences.fontSize,
      height: _preferences.lineHeight,
      fontFamily: _preferences.fontFamily == 'system-ui'
          ? null
          : _preferences.fontFamily,
      fontWeight:
          FontWeight.values[(_preferences.fontWeight ~/ 100 - 1).clamp(0, 8)],
      letterSpacing: _preferences.letterSpacing,
    );
    if (index < 0 || sentence == null) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, index)),
        TextSpan(
          text: sentence,
          style: const TextStyle(
            backgroundColor: Color(0xFFFFD54F),
            color: Colors.black,
          ),
        ),
        TextSpan(text: text.substring(index + sentence.length)),
      ],
    );
  }

  static Color _hexColor(String value) =>
      Color(0xFF000000 | int.parse(value.replaceFirst('#', ''), radix: 16));

  static Uint8List? _decodeDataUri(String value) {
    final comma = value.indexOf(',');
    if (comma < 0 || !value.substring(0, comma).contains(';base64')) {
      return null;
    }
    try {
      return base64Decode(value.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}

String _txtReaderClock() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

class _TxtCurlTurn {
  const _TxtCurlTurn({
    required this.current,
    required this.target,
    required this.targetIndex,
    required this.direction,
    required this.autoComplete,
    this.controller,
  });

  final ui.Image current;
  final ui.Image target;
  final int targetIndex;
  final double direction;
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

class _TxtDisplayText {
  const _TxtDisplayText({required this.text, required this.offsets});

  final String text;
  final List<int> offsets;

  int originalOffset(int displayOffset) =>
      offsets[displayOffset.clamp(0, offsets.length - 1)];
}
