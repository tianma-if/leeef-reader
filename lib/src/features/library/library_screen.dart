import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/ai/configured_translation_provider.dart';
import 'package:leeef_reader/src/ai/llm_assistant_provider.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/library_backup_service.dart';
import 'package:leeef_reader/src/data/library_maintenance_service.dart';
import 'package:leeef_reader/src/features/reader/reader_screen.dart';
import 'package:leeef_reader/src/features/opds/opds_screen.dart';
import 'package:leeef_reader/src/features/notes/excerpt_share_card_screen.dart';
import 'package:leeef_reader/src/features/ai/ai_assistant_screen.dart';
import 'package:leeef_reader/src/features/ai/ai_prompt_manager_screen.dart';
import 'package:leeef_reader/src/features/statistics/reading_statistics_screen.dart';
import 'package:leeef_reader/src/features/settings/trusted_devices_screen.dart';
import 'package:leeef_reader/src/export/note_export_service.dart';
import 'package:leeef_reader/src/sync/configured_sync_backend.dart';
import 'package:leeef_reader/src/sync/background_sync_scheduler.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/s3_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:leeef_reader/src/sync/sync_backend.dart';
import 'package:leeef_reader/src/sync/trusted/trusted_sync_service.dart';
import 'package:leeef_reader/src/sync/webdav_sync_backend.dart';
import 'package:leeef_reader/src/tts/configured_tts_engine.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/platform/app_log.dart';
import 'package:leeef_reader/src/platform/app_notifications.dart';
import 'package:leeef_reader/src/platform/app_proxy.dart';
import 'package:leeef_reader/src/platform/app_update_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _bookExtensions = ['epub', 'pdf', 'txt', 'mobi', 'azw3', 'fb2'];
  _AppSection _selectedSection = _AppSection.library;
  bool _isImporting = false;
  bool _isDragging = false;
  StreamSubscription<List<SharedMediaFile>>? _sharingSubscription;

  @override
  void initState() {
    super.initState();
    AppAppearanceController.instance.addListener(_appearanceChanged);
    if (Platform.isAndroid || Platform.isIOS) {
      _sharingSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((files) => unawaited(_handleSharedFiles(files)));
      ReceiveSharingIntent.instance.getInitialMedia().then((files) async {
        await _handleSharedFiles(files);
        await ReceiveSharingIntent.instance.reset();
      });
    }
  }

  @override
  void dispose() {
    AppAppearanceController.instance.removeListener(_appearanceChanged);
    _sharingSubscription?.cancel();
    super.dispose();
  }

  void _appearanceChanged() {
    if (!mounted) return;
    final visible = _visibleSections;
    setState(() {
      if (!visible.contains(_selectedSection)) {
        _selectedSection = _AppSection.library;
      }
    });
  }

  List<_AppSection> get _visibleSections => _AppSection.values
      .where(
        (section) => AppAppearanceController.instance.visibleNavigation
            .contains(section.name),
      )
      .toList();

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) =>
      _importPaths(files.map((file) => file.path), source: '分享');

  Future<void> _importBook() async {
    try {
      await AppLog.info('opening book import file picker');
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _bookExtensions,
      );
      final paths = result
          .map((file) => file.path)
          .whereType<String>()
          .toList();
      await AppLog.info(
        'book import file picker returned ${paths.length} path(s)',
      );
      await _importPaths(paths);
    } on Object catch (error, stackTrace) {
      await AppLog.error(error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('导入', error))),
      );
    }
  }

  Future<void> _importPaths(
    Iterable<String> candidatePaths, {
    String source = '选择',
  }) async {
    final candidates = candidatePaths.toList();
    final paths = candidates.where(_isSupportedBookPath).toSet().toList();
    if (paths.isEmpty || !mounted) {
      if (mounted && candidates.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).unsupportedFiles(source)),
          ),
        );
      }
      return;
    }
    if (_isImporting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('正在导入，请稍后重试'))),
      );
      return;
    }
    setState(() => _isImporting = true);
    try {
      final importer = await ref.read(bookImportServiceProvider.future);
      var imported = 0;
      final failures = <String>[];
      for (final path in paths) {
        try {
          await importer.importFile(File(path));
          imported++;
        } on Object catch (error) {
          failures.add('${File(path).uri.pathSegments.last}: $error');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(
              context,
            ).importCompleted(imported, failures.length, failures.firstOrNull),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('导入', error))),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  static bool _isSupportedBookPath(String path) {
    final lower = path.toLowerCase();
    return _bookExtensions.any((extension) => lower.endsWith('.$extension'));
  }

  Widget _dropOverlay(BuildContext context, Widget child) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (_isDragging)
        IgnorePointer(
          child: ColoredBox(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.92),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_download_outlined, size: 64),
                  SizedBox(height: 16),
                  Text(AppStrings.of(context).text('松开即可导入电子书')),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (detail) {
        setState(() => _isDragging = false);
        unawaited(
          _importPaths(detail.files.map((file) => file.path), source: '拖入'),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRail = constraints.maxWidth >= 720;
          final strings = AppStrings.of(context);
          final sections = _visibleSections;
          final selectedIndex = sections
              .indexOf(_selectedSection)
              .clamp(0, sections.length - 1);
          final title = switch (_selectedSection) {
            _AppSection.library => strings.library,
            _AppSection.notes => strings.notes,
            _AppSection.search => strings.search,
            _AppSection.statistics => strings.statistics,
            _AppSection.settings => strings.settings,
          };
          final content = switch (_selectedSection) {
            _AppSection.library => const _LibraryContent(),
            _AppSection.notes => const _ExcerptContent(),
            _AppSection.search => const _SearchContent(),
            _AppSection.statistics => const ReadingStatisticsScreen(),
            _AppSection.settings => const _SettingsContent(),
          };
          final importButton = _selectedSection == _AppSection.library
              ? FloatingActionButton.extended(
                  onPressed: _isImporting ? null : _importBook,
                  icon: _isImporting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isImporting ? '…' : strings.importBook),
                )
              : null;

          if (!useRail) {
            return _dropOverlay(
              context,
              Scaffold(
                appBar: AppBar(title: Text(title)),
                body: content,
                floatingActionButton: importButton,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedSection = sections[index]),
                  destinations: _destinations(strings, sections),
                ),
              ),
            );
          }

          return _dropOverlay(
            context,
            Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedSection = sections[index]),
                    labelType: NavigationRailLabelType.all,
                    destinations: _railDestinations(strings, sections),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Scaffold(
                      appBar: AppBar(title: Text(title)),
                      body: content,
                      floatingActionButton: importButton,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _AppSection { library, notes, search, statistics, settings }

List<NavigationDestination> _destinations(
  AppStrings strings,
  List<_AppSection> sections,
) => [
  for (final section in sections)
    NavigationDestination(
      icon: Icon(section.icon),
      selectedIcon: Icon(section.selectedIcon),
      label: section.label(strings),
    ),
];

List<NavigationRailDestination> _railDestinations(
  AppStrings strings,
  List<_AppSection> sections,
) => [
  for (final section in sections)
    NavigationRailDestination(
      icon: Icon(section.icon),
      selectedIcon: Icon(section.selectedIcon),
      label: Text(section.label(strings)),
    ),
];

extension on _AppSection {
  IconData get icon => switch (this) {
    _AppSection.library => Icons.local_library_outlined,
    _AppSection.notes => Icons.edit_note_outlined,
    _AppSection.search => Icons.search,
    _AppSection.statistics => Icons.insights_outlined,
    _AppSection.settings => Icons.settings_outlined,
  };
  IconData get selectedIcon =>
      this == _AppSection.library ? Icons.local_library : icon;
  String label(AppStrings strings) => switch (this) {
    _AppSection.library => strings.library,
    _AppSection.notes => strings.notes,
    _AppSection.search => strings.search,
    _AppSection.statistics => strings.statistics,
    _AppSection.settings => strings.settings,
  };
}

class _SearchContent extends ConsumerStatefulWidget {
  const _SearchContent();

  @override
  ConsumerState<_SearchContent> createState() => _SearchContentState();
}

class _SearchContentState extends ConsumerState<_SearchContent> {
  String _query = '';

  bool _matches(String? value) =>
      value?.toLowerCase().contains(_query.toLowerCase()) ?? false;

  void _openBook(BookRecord? book) {
    if (book == null) return;
    if (!book.isAvailableLocally) {
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.text('请先下载这本书'))));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(book: book)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final books = ref.watch(libraryBooksProvider);
    final excerpts = ref.watch(allExcerptsProvider);
    final bookmarks = ref.watch(allBookmarksProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchBar(
            leading: const Icon(Icons.search),
            hintText: strings.text('搜索书名、作者、书摘、笔记和书签'),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child: books.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(AppStrings.of(context).failure('搜索', error)),
            ),
            data: (bookItems) => excerpts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(AppStrings.of(context).failure('搜索', error)),
              ),
              data: (excerptItems) => bookmarks.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(AppStrings.of(context).failure('搜索', error)),
                ),
                data: (bookmarkItems) {
                  if (_query.isEmpty) {
                    return Center(child: Text(strings.text('输入关键词搜索整个书库')));
                  }
                  final byId = {for (final book in bookItems) book.id: book};
                  final matchedBooks = bookItems
                      .where(
                        (book) => _matches(book.title) || _matches(book.author),
                      )
                      .toList();
                  final matchedExcerpts = excerptItems
                      .where(
                        (item) => _matches(item.quote) || _matches(item.note),
                      )
                      .toList();
                  final matchedBookmarks = bookmarkItems
                      .where(
                        (item) => _matches(item.title) || _matches(item.note),
                      )
                      .toList();
                  if (matchedBooks.isEmpty &&
                      matchedExcerpts.isEmpty &&
                      matchedBookmarks.isEmpty) {
                    return Center(child: Text(strings.text('没有找到匹配内容')));
                  }
                  return ListView(
                    children: [
                      if (matchedBooks.isNotEmpty)
                        ListTile(title: Text(strings.text('书籍'))),
                      for (final book in matchedBooks)
                        ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(book.title),
                          subtitle: Text(book.author ?? strings.text('未知作者')),
                          onTap: () => _openBook(book),
                        ),
                      if (matchedExcerpts.isNotEmpty)
                        ListTile(title: Text(strings.text('书摘与笔记'))),
                      for (final excerpt in matchedExcerpts)
                        ListTile(
                          leading: const Icon(Icons.format_quote),
                          title: Text(
                            excerpt.quote,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${byId[excerpt.bookId]?.title ?? strings.text('未知书籍')}${excerpt.note == null ? '' : ' · ${excerpt.note}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openBook(byId[excerpt.bookId]),
                        ),
                      if (matchedBookmarks.isNotEmpty)
                        ListTile(title: Text(strings.text('书签'))),
                      for (final bookmark in matchedBookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(bookmark.title ?? strings.text('未命名书签')),
                          subtitle: Text(
                            '${byId[bookmark.bookId]?.title ?? strings.text('未知书籍')}${bookmark.note == null ? '' : ' · ${bookmark.note}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _openBook(byId[bookmark.bookId]),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryContent extends ConsumerStatefulWidget {
  const _LibraryContent();

  @override
  ConsumerState<_LibraryContent> createState() => _LibraryContentState();
}

class _LibraryContentState extends ConsumerState<_LibraryContent> {
  String? _selectedBookshelfId;
  String? _selectedTagId;
  _ReadingFilter _readingFilter = _ReadingFilter.all;
  _BookSort _bookSort = _BookSort.recent;
  bool _ascending = true;

  Future<String?> _askForName({String initialValue = ''}) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppStrings.of(context).text(initialValue.isEmpty ? '新建书架' : '重命名书架'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppStrings.of(context).text('名称'),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty ?? true ? null : result!.trim();
  }

  Future<void> _createBookshelf() async {
    final name = await _askForName();
    if (name == null) return;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      final id = await repository.createBookshelf(name: name);
      if (mounted) setState(() => _selectedBookshelfId = id);
    } on Object catch (error) {
      _showError('创建书架失败', error);
    }
  }

  Future<void> _renameBookshelf(BookshelfRecord shelf) async {
    final name = await _askForName(initialValue: shelf.name);
    if (name == null) return;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      await repository.renameBookshelf(shelf.id, name);
    } on Object catch (error) {
      _showError('重命名失败', error);
    }
  }

  Future<void> _deleteBookshelf(BookshelfRecord shelf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).dissolveShelf(shelf.name)),
        content: Text(AppStrings.of(context).text('书籍不会被删除，只会移出这个书架。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('解散')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      await repository.deleteBookshelf(shelf.id);
      if (mounted && _selectedBookshelfId == shelf.id) {
        setState(() => _selectedBookshelfId = null);
      }
    } on Object catch (error) {
      _showError('解散书架失败', error);
    }
  }

  void _showError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$action：$error')));
  }

  Future<void> _editTag([TagRecord? tag]) async {
    final controller = TextEditingController(text: tag?.name);
    var color = tag?.color ?? 0xFF4CAF50;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppStrings.of(context).text(tag == null ? '新建标签' : '编辑标签'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('标签名称'),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  for (final candidate in const [
                    0xFFF9A825,
                    0xFF4CAF50,
                    0xFF2196F3,
                    0xFFE91E63,
                    0xFF9C27B0,
                    0xFF795548,
                  ])
                    ChoiceChip(
                      label: const SizedBox.square(dimension: 12),
                      avatar: CircleAvatar(backgroundColor: Color(candidate)),
                      selected: color == candidate,
                      onSelected: (_) =>
                          setDialogState(() => color = candidate),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (controller.text.trim(), color)),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.isEmpty) return;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      if (tag == null) {
        await repository.createTag(name: result.$1, color: result.$2);
      } else {
        await repository.updateTag(
          tagId: tag.id,
          name: result.$1,
          color: result.$2,
        );
      }
    } on Object catch (error) {
      _showError('保存标签失败', error);
    }
  }

  Future<void> _manageTags() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final tags = ref.watch(tagsProvider);
          return SafeArea(
            child: SizedBox(
              height: 420,
              child: tags.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(AppStrings.of(context).failure('读取标签', error)),
                ),
                data: (items) => ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(AppStrings.of(context).text('新建标签')),
                      onTap: _editTag,
                    ),
                    for (final tag in items)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(tag.color),
                        ),
                        title: Text(tag.name),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: AppStrings.of(context).text('编辑'),
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editTag(tag),
                            ),
                            IconButton(
                              tooltip: AppStrings.of(context).text('删除'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final repository = await ref.read(
                                  libraryRepositoryProvider.future,
                                );
                                await repository.deleteTag(tag.id);
                                if (_selectedTagId == tag.id && mounted) {
                                  setState(() => _selectedTagId = null);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final books = ref.watch(libraryBooksProvider);
    final shelves = ref.watch(bookshelvesProvider);
    final tags = ref.watch(tagsProvider);
    final progresses = ref.watch(readingProgressesProvider);
    final selectedId = _selectedBookshelfId;
    final shelfBookIds = selectedId == null
        ? const AsyncValue<List<String>>.data(<String>[])
        : ref.watch(bookshelfBookIdsProvider(selectedId));
    final selectedTagId = _selectedTagId;
    final tagBookIds = selectedTagId == null
        ? const AsyncValue<List<String>>.data(<String>[])
        : ref.watch(tagBookIdsProvider(selectedTagId));
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: shelves.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Center(
              child: Text(AppStrings.of(context).failure('读取书架', error)),
            ),
            data: (items) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                ChoiceChip(
                  label: Text(strings.text('全部')),
                  selected: selectedId == null,
                  onSelected: (_) =>
                      setState(() => _selectedBookshelfId = null),
                ),
                const SizedBox(width: 8),
                for (final shelf in items) ...[
                  InputChip(
                    visualDensity:
                        AppAppearanceController.instance.shelfStyle == 'compact'
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    label: Text(_bookshelfLabel(shelf, items)),
                    selected: selectedId == shelf.id,
                    onSelected: (_) =>
                        setState(() => _selectedBookshelfId = shelf.id),
                    onPressed: () =>
                        setState(() => _selectedBookshelfId = shelf.id),
                    deleteIcon: const Icon(Icons.more_horiz, size: 18),
                    onDeleted: () => _showBookshelfMenu(shelf),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 18,
                  ),
                  label: Text(strings.text('新建书架')),
                  onPressed: _createBookshelf,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 58,
          child: tags.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Center(
              child: Text(AppStrings.of(context).failure('读取标签', error)),
            ),
            data: (items) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                FilterChip(
                  label: Text(strings.text('所有标签')),
                  selected: selectedTagId == null,
                  onSelected: (_) => setState(() => _selectedTagId = null),
                ),
                const SizedBox(width: 8),
                for (final tag in items) ...[
                  FilterChip(
                    avatar: CircleAvatar(backgroundColor: Color(tag.color)),
                    label: Text(tag.name),
                    selected: selectedTagId == tag.id,
                    onSelected: (_) => setState(() => _selectedTagId = tag.id),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(Icons.label_outline, size: 18),
                  label: Text(strings.text('管理标签')),
                  onPressed: _manageTags,
                ),
                const SizedBox(width: 12),
                DropdownButton<_ReadingFilter>(
                  value: _readingFilter,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value != null) setState(() => _readingFilter = value);
                  },
                  items: [
                    DropdownMenuItem(
                      value: _ReadingFilter.all,
                      child: Text(strings.text('全部状态')),
                    ),
                    DropdownMenuItem(
                      value: _ReadingFilter.notStarted,
                      child: Text(strings.text('未开始')),
                    ),
                    DropdownMenuItem(
                      value: _ReadingFilter.reading,
                      child: Text(strings.text('阅读中')),
                    ),
                    DropdownMenuItem(
                      value: _ReadingFilter.finished,
                      child: Text(strings.text('已读完')),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                DropdownButton<_BookSort>(
                  value: _bookSort,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value != null) setState(() => _bookSort = value);
                  },
                  items: [
                    DropdownMenuItem(
                      value: _BookSort.recent,
                      child: Text(strings.text('最近更新')),
                    ),
                    DropdownMenuItem(
                      value: _BookSort.title,
                      child: Text(strings.text('标题')),
                    ),
                    DropdownMenuItem(
                      value: _BookSort.author,
                      child: Text(strings.text('作者')),
                    ),
                    DropdownMenuItem(
                      value: _BookSort.progress,
                      child: Text(strings.text('阅读进度')),
                    ),
                    DropdownMenuItem(
                      value: _BookSort.imported,
                      child: Text(strings.text('导入时间')),
                    ),
                    DropdownMenuItem(
                      value: _BookSort.rating,
                      child: Text(strings.text('评分')),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: strings.text(_ascending ? '升序' : '降序'),
                  onPressed: () => setState(() => _ascending = !_ascending),
                  icon: Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: books.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(AppStrings.of(context).failure('读取书库', error)),
            ),
            data: (items) {
              if (items.isEmpty) return const _EmptyLibrary();
              return shelfBookIds.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text(AppStrings.of(context).failure('读取书架内容', error)),
                ),
                data: (bookIds) => tagBookIds.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(
                      AppStrings.of(context).failure('读取标签内容', error),
                    ),
                  ),
                  data: (tagIds) => progresses.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text(
                        AppStrings.of(context).failure('读取进度', error),
                      ),
                    ),
                    data: (progressItems) {
                      final progressByBook = {
                        for (final progress in progressItems)
                          progress.bookId: progress,
                      };
                      final visible = _filterAndSortBooks(
                        items,
                        shelfBookIds: selectedId == null
                            ? null
                            : bookIds.toSet(),
                        tagBookIds: selectedTagId == null
                            ? null
                            : tagIds.toSet(),
                        progressByBook: progressByBook,
                      );
                      if (visible.isEmpty) {
                        return Center(
                          child: Text(strings.text('没有符合当前筛选条件的书籍。')),
                        );
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent:
                              AppAppearanceController.instance.shelfStyle ==
                                  'compact'
                              ? 175
                              : 220,
                          mainAxisExtent:
                              AppAppearanceController.instance.shelfStyle ==
                                  'compact'
                              ? 235
                              : 270,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _BookCard(
                          book: visible[index],
                          progress: progressByBook[visible[index].id]?.progress,
                          coverFit: AppAppearanceController.instance.coverFit,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<BookRecord> _filterAndSortBooks(
    List<BookRecord> books, {
    required Set<String>? shelfBookIds,
    required Set<String>? tagBookIds,
    required Map<String, ReadingProgressRecord> progressByBook,
  }) {
    final result = books.where((book) {
      if (shelfBookIds != null && !shelfBookIds.contains(book.id)) return false;
      if (tagBookIds != null && !tagBookIds.contains(book.id)) return false;
      final progress = progressByBook[book.id]?.progress;
      return switch (_readingFilter) {
        _ReadingFilter.all => true,
        _ReadingFilter.notStarted => progress == null || progress <= 0,
        _ReadingFilter.reading =>
          progress != null && progress > 0 && progress < 0.999,
        _ReadingFilter.finished => progress != null && progress >= 0.999,
      };
    }).toList();
    int compare(BookRecord left, BookRecord right) {
      final order = switch (_bookSort) {
        _BookSort.title => left.title.toLowerCase().compareTo(
          right.title.toLowerCase(),
        ),
        _BookSort.author => (left.author ?? '').toLowerCase().compareTo(
          (right.author ?? '').toLowerCase(),
        ),
        _BookSort.recent => left.updatedAt.compareTo(right.updatedAt),
        _BookSort.progress =>
          (progressByBook[left.id]?.progress ?? 0).compareTo(
            progressByBook[right.id]?.progress ?? 0,
          ),
        _BookSort.imported => left.createdAt.compareTo(right.createdAt),
        _BookSort.rating => (left.rating ?? 0).compareTo(right.rating ?? 0),
      };
      return _ascending ? order : -order;
    }

    result.sort(compare);
    return result;
  }

  Future<void> _showBookshelfMenu(BookshelfRecord shelf) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(AppStrings.of(context).text('重命名')),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(AppStrings.of(context).text('移动到文件夹')),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(AppStrings.of(context).text('解散书架')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') await _renameBookshelf(shelf);
    if (action == 'move') await _moveBookshelf(shelf);
    if (action == 'delete') await _deleteBookshelf(shelf);
  }

  Future<void> _moveBookshelf(BookshelfRecord shelf) async {
    final shelves = await ref.read(bookshelvesProvider.future);
    if (!mounted) return;
    final destination = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppStrings.of(context).moveShelf(shelf.name)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text(AppStrings.of(context).text('顶层')),
            ),
          ),
          for (final candidate in shelves)
            if (candidate.id != shelf.id)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, candidate.id),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(_bookshelfLabel(candidate, shelves)),
                ),
              ),
        ],
      ),
    );
    if (destination == null) return;
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      await repository.moveBookshelf(
        bookshelfId: shelf.id,
        parentId: destination == '__root__' ? null : destination,
      );
    } on Object catch (error) {
      _showError('移动书架失败', error);
    }
  }

  static String _bookshelfLabel(
    BookshelfRecord shelf,
    List<BookshelfRecord> shelves,
  ) {
    final byId = {for (final item in shelves) item.id: item};
    final parts = <String>[shelf.name];
    final visited = <String>{shelf.id};
    var parentId = shelf.parentId;
    while (parentId != null && visited.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      parts.add(parent.name);
      parentId = parent.parentId;
    }
    return parts.reversed.join(' / ');
  }
}

enum _ReadingFilter { all, notStarted, reading, finished }

enum _BookSort { recent, title, author, progress, imported, rating }

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.book, this.progress, required this.coverFit});

  final BookRecord book;
  final double? progress;
  final BoxFit coverFit;

  Future<void> _share(BuildContext context) async {
    final path = book.filePath;
    if (path == null || !await File(path).exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).text('本地文件不存在'))),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        title: book.title,
        files: [XFile(path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _replace(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'pdf', 'txt', 'mobi', 'azw3', 'fb2'],
      dialogTitle: AppStrings.of(context).chooseNewBookFile(book.title),
    );
    final path = result?.path;
    if (path == null) return;
    try {
      final importer = await ref.read(bookImportServiceProvider.future);
      await importer.replaceFile(book: book, source: File(path));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('书籍文件已替换'))),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('替换', error))),
      );
    }
  }

  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).freeLocalCopy(book.title)),
        content: Text(
          AppStrings.of(context).text('只删除本机副本，书籍信息和云端文件会保留。之后可从同步后端重新下载。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('释放')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final importer = await ref.read(bookImportServiceProvider.future);
      await importer.releaseLocalCopy(book);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('本地副本已释放'))),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('释放', error))),
      );
    }
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final engine = SyncEngine(
        repository: await ref.read(libraryRepositoryProvider.future),
        backend: await loadConfiguredSyncBackend(),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      );
      final downloaded = await engine.downloadBook(book.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text(downloaded ? '书籍已下载到本机' : '云端尚无该书文件'),
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('下载', error))),
      );
    }
  }

  Future<void> _editBookshelves(BuildContext context, WidgetRef ref) async {
    final shelves = await ref.read(bookshelvesProvider.future);
    if (!context.mounted) return;
    if (shelves.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('请先新建一个书架。'))),
      );
      return;
    }
    final repository = await ref.read(libraryRepositoryProvider.future);
    final original = await repository.listBookBookshelfIds(book.id);
    if (!context.mounted) return;
    final selected = {...original};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).addBookToShelf(book.title)),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final shelf in shelves)
                  CheckboxListTile(
                    value: selected.contains(shelf.id),
                    title: Text(shelf.name),
                    onChanged: (checked) => setDialogState(() {
                      if (checked ?? false) {
                        selected.add(shelf.id);
                      } else {
                        selected.remove(shelf.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    for (final shelf in shelves) {
      if (result.contains(shelf.id) && !original.contains(shelf.id)) {
        await repository.addBookToBookshelf(
          bookshelfId: shelf.id,
          bookId: book.id,
        );
      } else if (!result.contains(shelf.id) && original.contains(shelf.id)) {
        await repository.removeBookFromBookshelf(
          bookshelfId: shelf.id,
          bookId: book.id,
        );
      }
    }
  }

  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    var tags = await ref.read(tagsProvider.future);
    if (!context.mounted) return;
    if (tags.isEmpty) {
      final strings = AppStrings.of(context);
      final name = await _askText(
        context,
        title: strings.text('新建标签'),
        label: strings.text('标签名称'),
      );
      if (name == null || !context.mounted) return;
      final repository = await ref.read(libraryRepositoryProvider.future);
      await repository.createTag(name: name, color: 0xFF4CAF50);
      ref.invalidate(tagsProvider);
      tags = await ref.read(tagsProvider.future);
    }
    final repository = await ref.read(libraryRepositoryProvider.future);
    final original = await repository.listBookTagIds(book.id);
    if (!context.mounted) return;
    final selected = {...original};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).setBookTags(book.title)),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final tag in tags)
                  CheckboxListTile(
                    value: selected.contains(tag.id),
                    secondary: CircleAvatar(backgroundColor: Color(tag.color)),
                    title: Text(tag.name),
                    onChanged: (checked) => setDialogState(() {
                      if (checked ?? false) {
                        selected.add(tag.id);
                      } else {
                        selected.remove(tag.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    for (final tag in tags) {
      if (result.contains(tag.id) && !original.contains(tag.id)) {
        await repository.addBookTag(tagId: tag.id, bookId: book.id);
      } else if (!result.contains(tag.id) && original.contains(tag.id)) {
        await repository.removeBookTag(tagId: tag.id, bookId: book.id);
      }
    }
  }

  Future<void> _editDetails(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController(text: book.title);
    final authorController = TextEditingController(text: book.author);
    final descriptionController = TextEditingController(text: book.description);
    var rating = book.rating ?? 0;
    final result = await showDialog<(String, String, String, double?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('编辑书籍详情')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('标题'),
                    ),
                  ),
                  TextField(
                    controller: authorController,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('作者'),
                    ),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('简介'),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(AppStrings.of(context).text('评分')),
                      Expanded(
                        child: Slider(
                          value: rating,
                          min: 0,
                          max: 5,
                          divisions: 10,
                          label: rating == 0
                              ? AppStrings.of(context).text('未评分')
                              : rating.toStringAsFixed(1),
                          onChanged: (value) =>
                              setDialogState(() => rating = value),
                        ),
                      ),
                      Text(rating == 0 ? '—' : rating.toStringAsFixed(1)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                titleController.text,
                authorController.text,
                descriptionController.text,
                rating == 0 ? null : rating,
              )),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    authorController.dispose();
    descriptionController.dispose();
    if (result == null) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.updateBookDetails(
      bookId: book.id,
      title: result.$1,
      author: result.$2,
      description: result.$3,
      rating: result.$4,
    );
  }

  Future<void> _deleteBook(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).deleteBookTitle(book.title)),
        content: Text(AppStrings.of(context).text('书籍、书摘、书签和阅读进度会从所有同步设备删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (book.isAvailableLocally) {
      final importer = await ref.read(bookImportServiceProvider.future);
      await importer.releaseLocalCopy(book);
    }
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.softDeleteBook(book.id);
  }

  static Future<String?> _askText(
    BuildContext context, {
    required String title,
    required String label,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (text) => Navigator.pop(context, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty ?? true ? null : value!.trim();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    return Semantics(
      button: true,
      label: strings.bookSemantics(
        book.title,
        book.author,
        cloudOnly: !book.isAvailableLocally,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: book.isAvailableLocally
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(book: book),
                  ),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: Hero(
                      tag: 'book-cover-${book.id}',
                      child:
                          book.coverPath != null &&
                              File(book.coverPath!).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(book.coverPath!),
                                fit: coverFit,
                                width: double.infinity,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.menu_book_rounded,
                                  size: 72,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : Icon(
                              book.isAvailableLocally
                                  ? Icons.menu_book_rounded
                                  : Icons.cloud_download_outlined,
                              size: 72,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                    ),
                  ),
                ),
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  book.author ?? strings.text('未知作者'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: progress!.clamp(0, 1)),
                ],
                Row(
                  children: [
                    if (book.rating != null) ...[
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                      Text(book.rating!.toStringAsFixed(1)),
                    ],
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: AppStrings.of(context).text('书籍操作'),
                      onSelected: (action) {
                        if (action == 'details') _editDetails(context, ref);
                        if (action == 'shelves') _editBookshelves(context, ref);
                        if (action == 'tags') _editTags(context, ref);
                        if (action == 'share') _share(context);
                        if (action == 'replace') _replace(context, ref);
                        if (action == 'release') _release(context, ref);
                        if (action == 'download') _download(context, ref);
                        if (action == 'delete') _deleteBook(context, ref);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'details',
                          child: Text(AppStrings.of(context).text('编辑详情与评分')),
                        ),
                        PopupMenuItem(
                          value: 'shelves',
                          child: Text(AppStrings.of(context).text('整理书架')),
                        ),
                        PopupMenuItem(
                          value: 'tags',
                          child: Text(AppStrings.of(context).text('设置标签')),
                        ),
                        if (book.isAvailableLocally)
                          PopupMenuItem(
                            value: 'share',
                            child: Text(AppStrings.of(context).text('分享文件')),
                          ),
                        if (!book.isAvailableLocally)
                          PopupMenuItem(
                            value: 'download',
                            child: Text(AppStrings.of(context).text('从云端重新下载')),
                          ),
                        PopupMenuItem(
                          value: 'replace',
                          child: Text(AppStrings.of(context).text('替换文件')),
                        ),
                        if (book.isAvailableLocally)
                          PopupMenuItem(
                            value: 'release',
                            child: Text(AppStrings.of(context).text('释放本地空间')),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(AppStrings.of(context).text('删除书籍')),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExcerptContent extends ConsumerStatefulWidget {
  const _ExcerptContent();

  @override
  ConsumerState<_ExcerptContent> createState() => _ExcerptContentState();
}

class _ExcerptContentState extends ConsumerState<_ExcerptContent> {
  bool _exporting = false;
  String _noteFilter = 'all';
  String _colorFilter = 'all';
  String _sort = 'newest';
  String? _bookFilter;
  final Set<String> _selectedExcerptIds = {};

  Future<void> _export(
    NoteExportFormat format, {
    bool clipboard = false,
    List<ExcerptRecord>? selectedExcerpts,
  }) async {
    if (_exporting) return;
    final exportDialogTitle = AppStrings.of(context).text('导出书摘与笔记');
    setState(() => _exporting = true);
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      final service = const NoteExportService();
      final content = service.export(
        excerpts: selectedExcerpts ?? await repository.listExcerpts(),
        books: await repository.listBooks(),
        format: format,
      );
      if (clipboard) {
        await Clipboard.setData(ClipboardData(text: content));
      } else {
        final extension = NoteExportService.extension(format);
        await FilePicker.saveFile(
          dialogTitle: exportDialogTitle,
          fileName: 'leeef-notes.$extension',
          type: FileType.custom,
          allowedExtensions: [extension],
          bytes: service.encode(content),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).text(clipboard ? '已复制到剪贴板' : '导出完成'),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('导出', error))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedExcerptIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppStrings.of(context).deleteExcerpts(_selectedExcerptIds.length),
        ),
        content: Text(AppStrings.of(context).text('批量删除会通过同步日志传播到其他设备。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    for (final id in _selectedExcerptIds.toList()) {
      await repository.deleteExcerpt(id);
    }
    if (mounted) setState(_selectedExcerptIds.clear);
  }

  Future<void> _batchSetColor(String color, List<ExcerptRecord> visible) async {
    final repository = await ref.read(libraryRepositoryProvider.future);
    final selected = visible.where(
      (item) => _selectedExcerptIds.contains(item.id),
    );
    for (final excerpt in selected) {
      await repository.updateExcerpt(
        excerptId: excerpt.id,
        note: excerpt.note ?? '',
        color: color,
      );
    }
    if (mounted) setState(_selectedExcerptIds.clear);
  }

  Future<void> _editExcerpt(ExcerptRecord excerpt) async {
    final noteController = TextEditingController(text: excerpt.note);
    var color = excerpt.color;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('编辑书摘')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(excerpt.quote, maxLines: 5, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('笔记'),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: color,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('标记颜色'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'yellow',
                    child: Text(AppStrings.of(context).text('黄色')),
                  ),
                  DropdownMenuItem(
                    value: 'green',
                    child: Text(AppStrings.of(context).text('绿色')),
                  ),
                  DropdownMenuItem(
                    value: 'blue',
                    child: Text(AppStrings.of(context).text('蓝色')),
                  ),
                  DropdownMenuItem(
                    value: 'pink',
                    child: Text(AppStrings.of(context).text('粉色')),
                  ),
                  DropdownMenuItem(
                    value: 'purple',
                    child: Text(AppStrings.of(context).text('紫色')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => color = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (noteController.text, color)),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (result == null) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.updateExcerpt(
      excerptId: excerpt.id,
      note: result.$1,
      color: result.$2,
    );
  }

  Future<void> _shareExcerpt(ExcerptRecord excerpt) async {
    final book = await (await ref.read(
      libraryRepositoryProvider.future,
    )).getBook(excerpt.bookId);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ExcerptShareCardScreen(
          quote: excerpt.quote,
          note: excerpt.note,
          book: book,
        ),
      ),
    );
  }

  Future<void> _editBookmark(BookmarkRecord bookmark) async {
    final titleController = TextEditingController(text: bookmark.title);
    final noteController = TextEditingController(text: bookmark.note);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('编辑书签')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).text('标题'),
              ),
            ),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).text('备注'),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              titleController.text,
              noteController.text,
            )),
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    titleController.dispose();
    noteController.dispose();
    if (result == null) return;
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.updateBookmark(
      bookmarkId: bookmark.id,
      title: result.$1,
      note: result.$2,
    );
  }

  Future<void> _deleteAnnotation({
    required String label,
    required Future<void> Function() delete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).deleteNamed(label)),
        content: Text(AppStrings.of(context).text('删除会同步到其他设备。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('删除')),
          ),
        ],
      ),
    );
    if (confirmed == true) await delete();
  }

  static Color _excerptColor(String color) => switch (color) {
    'green' => Colors.green,
    'blue' => Colors.blue,
    'pink' => Colors.pink,
    'purple' => Colors.purple,
    _ => Colors.amber,
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final excerpts = ref.watch(allExcerptsProvider);
    final bookmarks = ref.watch(allBookmarksProvider);
    final books = ref
        .watch(libraryBooksProvider)
        .when(
          data: (items) => items,
          loading: () => const <BookRecord>[],
          error: (_, _) => const <BookRecord>[],
        );
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PopupMenuButton<String>(
              enabled: !_exporting,
              tooltip: strings.text('导出'),
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
              onSelected: (value) {
                switch (value) {
                  case 'clipboard':
                    _export(NoteExportFormat.markdown, clipboard: true);
                  case 'markdown':
                    _export(NoteExportFormat.markdown);
                  case 'text':
                    _export(NoteExportFormat.text);
                  case 'csv':
                    _export(NoteExportFormat.csv);
                  case 'chapter':
                    _export(NoteExportFormat.chapterMerged);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'clipboard',
                  child: Text(strings.text('复制 Markdown')),
                ),
                PopupMenuItem(
                  value: 'markdown',
                  child: Text(strings.text('导出 Markdown')),
                ),
                PopupMenuItem(
                  value: 'text',
                  child: Text(strings.text('导出 TXT')),
                ),
                PopupMenuItem(
                  value: 'csv',
                  child: Text(strings.text('导出 CSV')),
                ),
                PopupMenuItem(
                  value: 'chapter',
                  child: Text(strings.text('按书合并章节导出')),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: excerpts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(AppStrings.of(context).failure('读取书摘', error)),
            ),
            data: (items) => bookmarks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(AppStrings.of(context).failure('读取书签', error)),
              ),
              data: (bookmarkItems) {
                final bookTitles = {
                  for (final book in books) book.id: book.title,
                };
                final visibleExcerpts =
                    items.where((excerpt) {
                      if (_bookFilter != null &&
                          excerpt.bookId != _bookFilter) {
                        return false;
                      }
                      if (_colorFilter != 'all' &&
                          excerpt.color != _colorFilter) {
                        return false;
                      }
                      final hasNote = excerpt.note?.trim().isNotEmpty == true;
                      return switch (_noteFilter) {
                        'notes' => hasNote,
                        'quotes' => !hasNote,
                        _ => true,
                      };
                    }).toList()..sort(
                      (left, right) => switch (_sort) {
                        'oldest' => left.createdAt.compareTo(right.createdAt),
                        'position' =>
                          left.bookId == right.bookId
                              ? left.locator.compareTo(right.locator)
                              : (bookTitles[left.bookId] ?? '').compareTo(
                                  bookTitles[right.bookId] ?? '',
                                ),
                        _ => right.createdAt.compareTo(left.createdAt),
                      },
                    );
                if (items.isEmpty && bookmarkItems.isEmpty) {
                  return Center(
                    child: Text(strings.text('选中书中文字可创建书摘，阅读时也可添加书签。')),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String?>(
                          value: _bookFilter,
                          hint: Text(strings.text('全部书籍')),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(strings.text('全部书籍')),
                            ),
                            for (final book in books)
                              DropdownMenuItem<String?>(
                                value: book.id,
                                child: Text(
                                  book.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _bookFilter = value),
                        ),
                        DropdownButton<String>(
                          value: _noteFilter,
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(strings.text('全部类型')),
                            ),
                            DropdownMenuItem(
                              value: 'notes',
                              child: Text(strings.text('有笔记')),
                            ),
                            DropdownMenuItem(
                              value: 'quotes',
                              child: Text(strings.text('仅书摘')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _noteFilter = value);
                            }
                          },
                        ),
                        DropdownButton<String>(
                          value: _colorFilter,
                          items: [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text(strings.text('全部颜色')),
                            ),
                            DropdownMenuItem(
                              value: 'yellow',
                              child: Text(strings.text('黄色')),
                            ),
                            DropdownMenuItem(
                              value: 'green',
                              child: Text(strings.text('绿色')),
                            ),
                            DropdownMenuItem(
                              value: 'blue',
                              child: Text(strings.text('蓝色')),
                            ),
                            DropdownMenuItem(
                              value: 'pink',
                              child: Text(strings.text('粉色')),
                            ),
                            DropdownMenuItem(
                              value: 'purple',
                              child: Text(strings.text('紫色')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _colorFilter = value);
                            }
                          },
                        ),
                        DropdownButton<String>(
                          value: _sort,
                          items: [
                            DropdownMenuItem(
                              value: 'newest',
                              child: Text(strings.text('最新优先')),
                            ),
                            DropdownMenuItem(
                              value: 'oldest',
                              child: Text(strings.text('最早优先')),
                            ),
                            DropdownMenuItem(
                              value: 'position',
                              child: Text(strings.text('按书与章节')),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _sort = value);
                          },
                        ),
                      ],
                    ),
                    if (_selectedExcerptIds.isNotEmpty)
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '已选 ${_selectedExcerptIds.length} 条',
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: AppStrings.of(context).text('批量修改颜色'),
                                icon: const Icon(Icons.palette_outlined),
                                onSelected: (color) =>
                                    _batchSetColor(color, visibleExcerpts),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'yellow',
                                    child: Text(
                                      AppStrings.of(context).text('黄色'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'green',
                                    child: Text(
                                      AppStrings.of(context).text('绿色'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'blue',
                                    child: Text(
                                      AppStrings.of(context).text('蓝色'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'pink',
                                    child: Text(
                                      AppStrings.of(context).text('粉色'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'purple',
                                    child: Text(
                                      AppStrings.of(context).text('紫色'),
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                tooltip: AppStrings.of(context).text('导出所选'),
                                onPressed: () => _export(
                                  NoteExportFormat.markdown,
                                  selectedExcerpts: visibleExcerpts
                                      .where(
                                        (item) => _selectedExcerptIds.contains(
                                          item.id,
                                        ),
                                      )
                                      .toList(),
                                ),
                                icon: const Icon(Icons.ios_share_outlined),
                              ),
                              IconButton(
                                tooltip: AppStrings.of(context).text('批量删除'),
                                onPressed: _batchDelete,
                                icon: const Icon(Icons.delete_outline),
                              ),
                              IconButton(
                                tooltip: AppStrings.of(context).text('取消选择'),
                                onPressed: () =>
                                    setState(_selectedExcerptIds.clear),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (items.isNotEmpty) ...[
                      Text(
                        '书摘与笔记',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (visibleExcerpts.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              AppStrings.of(context).text('没有符合筛选条件的书摘'),
                            ),
                          ),
                        ),
                      for (final excerpt in visibleExcerpts)
                        Card(
                          child: ListTile(
                            selected: _selectedExcerptIds.contains(excerpt.id),
                            onLongPress: () => setState(
                              () => _selectedExcerptIds.add(excerpt.id),
                            ),
                            onTap: _selectedExcerptIds.isEmpty
                                ? null
                                : () => setState(() {
                                    if (!_selectedExcerptIds.remove(
                                      excerpt.id,
                                    )) {
                                      _selectedExcerptIds.add(excerpt.id);
                                    }
                                  }),
                            leading: _selectedExcerptIds.isEmpty
                                ? Icon(
                                    Icons.format_quote,
                                    color: _excerptColor(excerpt.color),
                                  )
                                : Checkbox(
                                    value: _selectedExcerptIds.contains(
                                      excerpt.id,
                                    ),
                                    onChanged: (_) => setState(() {
                                      if (!_selectedExcerptIds.remove(
                                        excerpt.id,
                                      )) {
                                        _selectedExcerptIds.add(excerpt.id);
                                      }
                                    }),
                                  ),
                            title: Text(excerpt.quote),
                            subtitle: Text(
                              [
                                ?bookTitles[excerpt.bookId],
                                ?excerpt.note,
                                excerpt.createdAt
                                    .toLocal()
                                    .toString()
                                    .substring(0, 16),
                              ].join('\n'),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') _editExcerpt(excerpt);
                                if (action == 'share') _shareExcerpt(excerpt);
                                if (action == 'delete') {
                                  _deleteAnnotation(
                                    label: strings.text('书摘'),
                                    delete: () async {
                                      final repository = await ref.read(
                                        libraryRepositoryProvider.future,
                                      );
                                      await repository.deleteExcerpt(
                                        excerpt.id,
                                      );
                                    },
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(
                                    AppStrings.of(context).text('编辑'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'share',
                                  child: Text(
                                    AppStrings.of(context).text('生成分享卡片'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    AppStrings.of(context).text('删除'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (bookmarkItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '书签',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final bookmark in bookmarkItems)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.bookmark_outline),
                            title: Text(
                              bookmark.title ?? strings.text('未命名书签'),
                            ),
                            subtitle: bookmark.note == null
                                ? Text(bookmark.locator)
                                : Text(bookmark.note!),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') _editBookmark(bookmark);
                                if (action == 'delete') {
                                  _deleteAnnotation(
                                    label: strings.text('书签'),
                                    delete: () async {
                                      final repository = await ref.read(
                                        libraryRepositoryProvider.future,
                                      );
                                      await repository.deleteBookmark(
                                        bookmark.id,
                                      );
                                    },
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(
                                    AppStrings.of(context).text('编辑'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    AppStrings.of(context).text('删除'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  static const _autoSyncKey = 'leeef.sync.auto';
  static const _wifiOnlyKey = 'leeef.sync.wifi_only';
  static const _syncDirectoryKey = 'leeef.sync.directory';
  static const _syncBackendKey = 'leeef.sync.backend';
  static const _webDavUrlKey = 'leeef.sync.webdav.url';
  static const _webDavUsernameKey = 'leeef.sync.webdav.username';
  static const _webDavPasswordKey = 'leeef.sync.webdav.password';
  static const _s3EndpointKey = 'leeef.sync.s3.endpoint';
  static const _s3BucketKey = 'leeef.sync.s3.bucket';
  static const _s3RegionKey = 'leeef.sync.s3.region';
  static const _s3PrefixKey = 'leeef.sync.s3.prefix';
  static const _s3PathStyleKey = 'leeef.sync.s3.path_style';
  static const _s3AccessKeyIdKey = 'leeef.sync.s3.access_key_id';
  static const _s3SecretAccessKeyKey = 'leeef.sync.s3.secret_access_key';
  static const _s3SessionTokenKey = 'leeef.sync.s3.session_token';
  static const _secureStorage = FlutterSecureStorage();
  String? _syncDirectory;
  String? _webDavUrl;
  String? _webDavUsername;
  String? _s3Endpoint;
  String? _s3Bucket;
  String _s3Region = 'us-east-1';
  String _s3Prefix = 'leeef';
  bool _s3PathStyle = true;
  _SyncBackendKind _syncBackend = _SyncBackendKind.s3;
  bool _busy = false;
  bool _autoSync = true;
  bool _wifiOnly = false;
  bool _syncNotifications = true;
  String? _aiBaseUrl;
  String? _aiModel;
  LibraryStorageReport? _storageReport;
  TtsService _ttsService = TtsService.system;
  String _locale = 'system';
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF356A45);
  String? _customDirectory;
  String? _proxyHost;
  int? _proxyPort;
  bool _developerMode = false;
  bool _epubJavaScript = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettingsPreferences());
    unawaited(_refreshStorage());
  }

  Future<void> _loadSettingsPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _syncDirectory = preferences.getString(_syncDirectoryKey);
      _webDavUrl = preferences.getString(_webDavUrlKey);
      _webDavUsername = preferences.getString(_webDavUsernameKey);
      _s3Endpoint = preferences.getString(_s3EndpointKey);
      _s3Bucket = preferences.getString(_s3BucketKey);
      _s3Region = preferences.getString(_s3RegionKey) ?? 'us-east-1';
      _s3Prefix = preferences.getString(_s3PrefixKey) ?? 'leeef';
      _s3PathStyle = preferences.getBool(_s3PathStyleKey) ?? true;
      _autoSync = preferences.getBool(_autoSyncKey) ?? true;
      _wifiOnly = preferences.getBool(_wifiOnlyKey) ?? false;
      _syncNotifications =
          preferences.getBool('leeef.sync.completion_notifications') ?? true;
      _aiBaseUrl = preferences.getString(aiBaseUrlPreferenceKey);
      _aiModel = preferences.getString(aiModelPreferenceKey);
      _ttsService = TtsService.values.firstWhere(
        (item) => item.name == preferences.getString(ttsServicePreferenceKey),
        orElse: () => TtsService.system,
      );
      _locale = preferences.getString('leeef.appearance.locale') ?? 'system';
      _themeMode = ThemeMode.values.firstWhere(
        (item) =>
            item.name == preferences.getString('leeef.appearance.theme_mode'),
        orElse: () => ThemeMode.system,
      );
      _seedColor = Color(
        preferences.getInt('leeef.appearance.seed_color') ?? 0xFF356A45,
      );
      _customDirectory = preferences.getString(
        'leeef.storage.custom_directory',
      );
      _proxyHost = preferences.getString(AppProxy.hostKey);
      _proxyPort = preferences.getInt(AppProxy.portKey);
      _developerMode = preferences.getBool('leeef.developer.enabled') ?? false;
      _epubJavaScript =
          preferences.getBool('leeef.reader.epub_javascript') ?? false;
      _syncBackend = _SyncBackendKind.values.firstWhere(
        (item) => item.name == preferences.getString(_syncBackendKey),
        orElse: () => _SyncBackendKind.s3,
      );
    });
  }

  Future<LibraryMaintenanceService> _maintenanceService() async =>
      LibraryMaintenanceService(
        repository: await ref.read(libraryRepositoryProvider.future),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      );

  Future<void> _refreshStorage() async {
    final report = await (await _maintenanceService()).inspect();
    if (mounted) setState(() => _storageReport = report);
  }

  Future<void> _showStorageDetails() async {
    final books = await (await ref.read(
      libraryRepositoryProvider.future,
    )).listBooks();
    final details =
        <({BookRecord book, int bookBytes, int coverBytes, bool missing})>[];
    for (final book in books) {
      final bookFile = book.filePath == null ? null : File(book.filePath!);
      final coverFile = book.coverPath == null ? null : File(book.coverPath!);
      final bookExists = bookFile != null && await bookFile.exists();
      details.add((
        book: book,
        bookBytes: bookExists ? await bookFile.length() : 0,
        coverBytes: coverFile != null && await coverFile.exists()
            ? await coverFile.length()
            : 0,
        missing: book.isAvailableLocally && !bookExists,
      ));
    }
    details.sort((a, b) => b.bookBytes.compareTo(a.bookBytes));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('本地文件明细')),
        content: SizedBox(
          width: 680,
          height: 520,
          child: details.isEmpty
              ? Center(child: Text(AppStrings.of(context).text('书库中还没有文件')))
              : ListView.builder(
                  itemCount: details.length,
                  itemBuilder: (context, index) {
                    final item = details[index];
                    return ListTile(
                      leading: Icon(
                        item.missing
                            ? Icons.warning_amber_rounded
                            : item.bookBytes == 0
                            ? Icons.cloud_outlined
                            : Icons.description_outlined,
                      ),
                      title: Text(item.book.title),
                      subtitle: Text(
                        item.missing
                            ? AppStrings.of(context).text('数据库记录为本地可用，但文件已缺失')
                            : item.bookBytes == 0
                            ? AppStrings.of(context).text('仅云端/元数据')
                            : AppStrings.of(context).storageFileSummary(
                                item.book.filePath ?? '',
                                _formatBytes(item.bookBytes),
                                _formatBytes(item.coverBytes),
                              ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: item.bookBytes > 0,
                    );
                  },
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('关闭')),
          ),
        ],
      ),
    );
  }

  Future<void> _manageFonts() async {
    final preferences = await SharedPreferences.getInstance();
    var name = preferences.getString('leeef.reader.imported_font_name') ?? '';
    var data = preferences.getString('leeef.reader.imported_font_data') ?? '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('阅读字体管理')),
          content: SizedBox(
            width: 520,
            child: ListTile(
              leading: const Icon(Icons.font_download_outlined),
              title: Text(
                name.isEmpty ? AppStrings.of(context).text('尚未导入字体') : name,
              ),
              subtitle: Text(
                name.isEmpty
                    ? AppStrings.of(
                        context,
                      ).text('可导入 TTF、OTF、WOFF 或 WOFF2，所有流式阅读器共用')
                    : AppStrings.of(
                        context,
                      ).cacheUsage(_formatBytes(data.length * 3 ~/ 4)),
              ),
              trailing: name.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AppStrings.of(context).text('删除字体'),
                      onPressed: () async {
                        await preferences.remove(
                          'leeef.reader.imported_font_name',
                        );
                        await preferences.remove(
                          'leeef.reader.imported_font_data',
                        );
                        await preferences.setString(
                          'leeef.reader.font_family',
                          'serif',
                        );
                        setDialogState(() {
                          name = '';
                          data = '';
                        });
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
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
                final encoded = 'data:$mime;base64,${base64Encode(bytes)}';
                await preferences.setString(
                  'leeef.reader.imported_font_name',
                  file.name,
                );
                await preferences.setString(
                  'leeef.reader.imported_font_data',
                  encoded,
                );
                await preferences.setString(
                  'leeef.reader.font_family',
                  'LeeefImportedFont',
                );
                setDialogState(() {
                  name = file.name;
                  data = encoded;
                });
              },
              icon: const Icon(Icons.file_open),
              label: Text(
                AppStrings.of(context).text(name.isEmpty ? '导入字体' : '替换字体'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('完成')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDataDirectory() async {
    if (_busy) return;
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: AppStrings.of(context).text('选择 Leeef 书籍数据目录'),
    );
    if (!mounted || path == null || path == _customDirectory) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('迁移本地书籍数据？')),
        content: Text(AppStrings.of(context).migrationTarget(path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('开始迁移')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await (await _maintenanceService()).migrateFilesTo(
        Directory(path),
      );
      await ref.read(appDatabaseProvider).copyToDirectory(Directory(path));
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('leeef.storage.custom_directory', path);
      await preferences.setBool('leeef.storage.database_restart_pending', true);
      ref.invalidate(libraryDirectoryProvider);
      ref.invalidate(libraryBooksProvider);
      if (mounted) {
        setState(() => _customDirectory = path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).migrationCompleted(count)),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).failure('迁移', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureProxy() async {
    final host = TextEditingController(text: _proxyHost);
    final port = TextEditingController(text: _proxyPort?.toString());
    final result = await showDialog<(String, int)?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('HTTP/HTTPS 代理')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: host,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).text('代理主机'),
              ),
            ),
            TextField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).text('端口'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ('', 0)),
            child: Text(AppStrings.of(context).text('停用')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(port.text.trim());
              if (host.text.trim().isNotEmpty &&
                  value != null &&
                  value > 0 &&
                  value <= 65535) {
                Navigator.pop(context, (host.text.trim(), value));
              }
            },
            child: Text(AppStrings.of(context).text('应用')),
          ),
        ],
      ),
    );
    host.dispose();
    port.dispose();
    if (result == null) return;
    final preferences = await SharedPreferences.getInstance();
    if (result.$1.isEmpty) {
      await preferences.remove(AppProxy.hostKey);
      await preferences.remove(AppProxy.portKey);
      AppProxy.apply(null, null);
      if (mounted) {
        setState(() {
          _proxyHost = null;
          _proxyPort = null;
        });
      }
    } else {
      await preferences.setString(AppProxy.hostKey, result.$1);
      await preferences.setInt(AppProxy.portKey, result.$2);
      AppProxy.apply(result.$1, result.$2);
      if (mounted) {
        setState(() {
          _proxyHost = result.$1;
          _proxyPort = result.$2;
        });
      }
    }
  }

  Future<void> _showLogs() async {
    var content = await AppLog.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('应用日志')),
          content: SizedBox(
            width: 720,
            height: 480,
            child: content.isEmpty
                ? Center(child: Text(AppStrings.of(context).text('日志为空')))
                : SingleChildScrollView(child: SelectableText(content)),
          ),
          actions: [
            TextButton.icon(
              onPressed: content.isEmpty
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: content)),
              icon: const Icon(Icons.copy),
              label: Text(AppStrings.of(context).text('复制')),
            ),
            TextButton.icon(
              onPressed: content.isEmpty
                  ? null
                  : () async {
                      await AppLog.clear();
                      setDialogState(() => content = '');
                    },
              icon: const Icon(Icons.delete_outline),
              label: Text(AppStrings.of(context).text('清空')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('关闭')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final update = await const AppUpdateService().check();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            AppStrings.of(
              context,
            ).updateTitle(update.updateAvailable, update.latestVersion),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                AppStrings.of(context).updateDetails(
                  update.currentVersion,
                  update.latestVersion,
                  update.releaseNotes,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('关闭')),
            ),
            FilledButton.icon(
              onPressed: () => launchUrl(
                update.releaseUrl,
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(AppStrings.of(context).text('查看发布页')),
            ),
          ],
        ),
      );
    } on Object catch (error, stackTrace) {
      await AppLog.error(error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).failure('检查更新', error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetOnboardingAndTips() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('leeef.onboarding.completed', false);
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('leeef.hint.'),
    )) {
      await preferences.remove(key);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text('引导与提示已重置，下次启动时生效')),
        ),
      );
    }
  }

  Future<void> _runMaintenance(
    Future<int> Function(LibraryMaintenanceService) action,
    String label,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action(await _maintenanceService());
      await _refreshStorage();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label：$result')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).failure(label, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBackend(_SyncBackendKind backend) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_syncBackendKey, backend.name);
    if (mounted) setState(() => _syncBackend = backend);
  }

  Future<void> _setAutoSync(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoSyncKey, value);
    await BackgroundSyncScheduler.configure(
      enabled: value,
      wifiOnly: _wifiOnly,
    );
    if (mounted) setState(() => _autoSync = value);
  }

  Future<void> _setWifiOnly(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_wifiOnlyKey, value);
    await BackgroundSyncScheduler.configure(
      enabled: _autoSync,
      wifiOnly: value,
    );
    if (mounted) setState(() => _wifiOnly = value);
  }

  Future<void> _configureAi() async {
    final preferences = await SharedPreferences.getInstance();
    final baseController = TextEditingController(
      text: _aiBaseUrl ?? 'https://api.openai.com/v1',
    );
    final modelController = TextEditingController(
      text: _aiModel ?? 'gpt-4.1-mini',
    );
    final keyController = TextEditingController(
      text: await _secureStorage.read(key: aiApiKeySecureKey) ?? '',
    );
    final promptController = TextEditingController(
      text:
          preferences.getString(aiPromptPreferenceKey) ??
          '你是电子书阅读器中的翻译助手。结合上下文准确翻译选中文本，保持人名、术语、语气与文体一致；先给译文，再用一句话解释有歧义的词语。不要续写原文。',
    );
    if (!mounted) return;
    final result = await showDialog<(String, String, String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('配置 AI 翻译')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baseController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(
                      context,
                    ).text('OpenAI-compatible API 地址'),
                  ),
                ),
                TextField(
                  controller: modelController,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).text('模型'),
                  ),
                ),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                TextField(
                  controller: promptController,
                  minLines: 3,
                  maxLines: 7,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).text('翻译 Prompt'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(baseController.text.trim());
              if (uri == null ||
                  !uri.hasScheme ||
                  uri.host.isEmpty ||
                  modelController.text.trim().isEmpty ||
                  keyController.text.isEmpty) {
                return;
              }
              Navigator.pop(context, (
                uri.toString(),
                modelController.text.trim(),
                keyController.text,
                promptController.text.trim(),
              ));
            },
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    baseController.dispose();
    modelController.dispose();
    keyController.dispose();
    promptController.dispose();
    if (result == null) return;
    await Future.wait([
      preferences.setString(aiBaseUrlPreferenceKey, result.$1),
      preferences.setString(aiModelPreferenceKey, result.$2),
      preferences.setString(aiPromptPreferenceKey, result.$4),
      _secureStorage.write(key: aiApiKeySecureKey, value: result.$3),
    ]);
    if (mounted) {
      setState(() {
        _aiBaseUrl = result.$1;
        _aiModel = result.$2;
      });
    }
  }

  Future<void> _testAi() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final provider = await loadConfiguredTranslationProvider();
      try {
        await provider.verifyConnection();
      } finally {
        provider.close();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('AI 模型连接正常'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).failure('检测 AI 模型', error)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureAiAdvanced() async {
    final preferences = await SharedPreferences.getInstance();
    var provider = AiProviderKind.values.firstWhere(
      (item) => item.name == preferences.getString(aiProviderPreferenceKey),
      orElse: () => AiProviderKind.openAiCompatible,
    );
    var reasoning =
        preferences.getString(aiReasoningEffortPreferenceKey) ?? 'medium';
    var libraryTool = preferences.getBool(aiLibraryToolPreferenceKey) ?? true;
    var notesTool = preferences.getBool(aiNotesToolPreferenceKey) ?? true;
    var historyTool = preferences.getBool(aiHistoryToolPreferenceKey) ?? true;
    var writeTools = preferences.getBool(aiWriteToolsPreferenceKey) ?? false;
    final prompt = TextEditingController(
      text:
          preferences.getString(aiAssistantPromptPreferenceKey) ??
          '你是 Leeef Reader 的阅读助手。仅依据提供的上下文回答，清楚区分事实与推断，引用原文时不要伪造内容。',
    );
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppStrings.of(context).text('AI Provider、Prompt 与 Tools'),
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<AiProviderKind>(
                    initialValue: provider,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('请求协议'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AiProviderKind.openAiCompatible,
                        child: Text(
                          'OpenAI-compatible / DeepSeek / OpenRouter',
                        ),
                      ),
                      DropdownMenuItem(
                        value: AiProviderKind.anthropic,
                        child: Text(
                          AppStrings.of(context).text('Claude / Anthropic 原生'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: AiProviderKind.gemini,
                        child: Text(AppStrings.of(context).text('Gemini 原生')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => provider = value);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: reasoning,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('推理强度'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'low',
                        child: Text(AppStrings.of(context).text('低（更省）')),
                      ),
                      DropdownMenuItem(
                        value: 'medium',
                        child: Text(AppStrings.of(context).text('中')),
                      ),
                      DropdownMenuItem(
                        value: 'high',
                        child: Text(AppStrings.of(context).text('高')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => reasoning = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prompt,
                    minLines: 4,
                    maxLines: 9,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('阅读助手 Prompt'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppStrings.of(context).text('书库查询 Tool')),
                    value: libraryTool,
                    onChanged: (value) =>
                        setDialogState(() => libraryTool = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppStrings.of(context).text('书摘与笔记 Tool')),
                    value: notesTool,
                    onChanged: (value) =>
                        setDialogState(() => notesTool = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppStrings.of(context).text('阅读历史 Tool')),
                    value: historyTool,
                    onChanged: (value) =>
                        setDialogState(() => historyTool = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppStrings.of(context).text('书库整理写入 Tools')),
                    subtitle: Text(
                      AppStrings.of(
                        context,
                      ).text('仅生成结构化计划；每次执行前仍需人工确认并写入审计日志'),
                    ),
                    value: writeTools,
                    onChanged: (value) =>
                        setDialogState(() => writeTools = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await Future.wait([
        preferences.setString(aiProviderPreferenceKey, provider.name),
        preferences.setString(aiReasoningEffortPreferenceKey, reasoning),
        preferences.setString(
          aiAssistantPromptPreferenceKey,
          prompt.text.trim(),
        ),
        preferences.setBool(aiLibraryToolPreferenceKey, libraryTool),
        preferences.setBool(aiNotesToolPreferenceKey, notesTool),
        preferences.setBool(aiHistoryToolPreferenceKey, historyTool),
        preferences.setBool(aiWriteToolsPreferenceKey, writeTools),
      ]);
    }
    prompt.dispose();
  }

  Future<void> _configureTts() async {
    final preferences = await SharedPreferences.getInstance();
    var service = _ttsService;
    var mixing = preferences.getString(ttsMixingPreferenceKey) ?? 'interrupt';
    final baseUrl = TextEditingController(
      text: preferences.getString(ttsBaseUrlPreferenceKey),
    );
    final model = TextEditingController(
      text: preferences.getString(ttsModelPreferenceKey) ?? 'gpt-4o-mini-tts',
    );
    final voice = TextEditingController(
      text: preferences.getString(ttsNetworkVoicePreferenceKey),
    );
    final region = TextEditingController(
      text: preferences.getString(ttsRegionPreferenceKey) ?? 'eastasia',
    );
    final appKey = TextEditingController(
      text: preferences.getString(ttsAppKeyPreferenceKey),
    );
    final apiKey = TextEditingController(
      text: await _secureStorage.read(key: ttsApiKeySecureKey),
    );
    if (!mounted) return;
    final result = await showDialog<TtsService>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('配置 TTS 服务')),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TtsService>(
                    initialValue: service,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('服务'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: TtsService.system,
                        child: Text(AppStrings.of(context).text('系统 TTS')),
                      ),
                      DropdownMenuItem(
                        value: TtsService.openAi,
                        child: Text('OpenAI TTS'),
                      ),
                      DropdownMenuItem(
                        value: TtsService.azure,
                        child: Text('Azure Speech'),
                      ),
                      DropdownMenuItem(
                        value: TtsService.alibaba,
                        child: Text(AppStrings.of(context).text('阿里云智能语音')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => service = value);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: mixing,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('与其他音频的混合方式'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'interrupt',
                        child: Text(AppStrings.of(context).text('暂停其他音频')),
                      ),
                      DropdownMenuItem(
                        value: 'duck',
                        child: Text(AppStrings.of(context).text('降低其他音频音量')),
                      ),
                      DropdownMenuItem(
                        value: 'mix',
                        child: Text(AppStrings.of(context).text('与其他音频同时播放')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => mixing = value);
                    },
                  ),
                  if (service != TtsService.system) ...[
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: service == TtsService.alibaba
                            ? 'Token'
                            : 'API Key',
                      ),
                    ),
                    TextField(
                      controller: baseUrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(
                          context,
                        ).text('Endpoint（留空使用默认值）'),
                      ),
                    ),
                    TextField(
                      controller: voice,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(
                          context,
                        ).text('Voice（留空使用默认声音）'),
                      ),
                    ),
                  ],
                  if (service == TtsService.openAi)
                    TextField(
                      controller: model,
                      decoration: InputDecoration(
                        labelText: AppStrings.of(context).text('模型'),
                      ),
                    ),
                  if (service == TtsService.azure)
                    TextField(
                      controller: region,
                      decoration: const InputDecoration(labelText: 'Region'),
                    ),
                  if (service == TtsService.alibaba)
                    TextField(
                      controller: appKey,
                      decoration: const InputDecoration(labelText: 'AppKey'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, service),
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await Future.wait([
        preferences.setString(ttsServicePreferenceKey, result.name),
        preferences.setString(ttsBaseUrlPreferenceKey, baseUrl.text.trim()),
        preferences.setString(ttsModelPreferenceKey, model.text.trim()),
        preferences.setString(ttsNetworkVoicePreferenceKey, voice.text.trim()),
        preferences.setString(ttsRegionPreferenceKey, region.text.trim()),
        preferences.setString(ttsAppKeyPreferenceKey, appKey.text.trim()),
        preferences.setString(ttsMixingPreferenceKey, mixing),
        _secureStorage.write(
          key: ttsApiKeySecureKey,
          value: apiKey.text.trim(),
        ),
      ]);
      if (mounted) setState(() => _ttsService = result);
    }
    baseUrl.dispose();
    model.dispose();
    voice.dispose();
    region.dispose();
    appKey.dispose();
    apiKey.dispose();
  }

  Future<void> _exportBackup() async {
    if (_busy) return;
    final exportDialogTitle = AppStrings.of(context).text('导出 Leeef 完整备份');
    setState(() => _busy = true);
    final temporary = await Directory.systemTemp.createTemp('leeef-export-');
    try {
      final archive = File('${temporary.path}/leeef-library.leeef-backup');
      final report = await LibraryBackupService(
        database: ref.read(appDatabaseProvider),
      ).exportTo(archive);
      await FilePicker.saveFile(
        dialogTitle: exportDialogTitle,
        fileName:
            'leeef-${DateTime.now().toIso8601String().substring(0, 10)}.leeef-backup',
        type: FileType.custom,
        allowedExtensions: const ['leeef-backup'],
        bytes: await archive.readAsBytes(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).backupCompleted(report.books, report.files),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).failure('备份', error))),
        );
      }
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final selection = await FilePicker.pickFiles(
      dialogTitle: AppStrings.of(context).text('选择 Leeef 完整备份'),
      type: FileType.custom,
      allowedExtensions: const ['leeef-backup', 'zip'],
    );
    final path = selection.firstOrNull?.path;
    if (path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('恢复完整备份？')),
        content: Text(
          AppStrings.of(
            context,
          ).text('当前书库数据会被备份内容替换。恢复前会完整校验文件，失败时数据库不会发生变化。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.of(context).text('恢复')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final report =
          await LibraryBackupService(
            database: ref.read(appDatabaseProvider),
          ).restoreFrom(
            File(path),
            await ref.read(libraryDirectoryProvider.future),
          );
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(allExcerptsProvider);
      ref.invalidate(allBookmarksProvider);
      ref.invalidate(bookshelvesProvider);
      ref.invalidate(tagsProvider);
      ref.invalidate(readingProgressesProvider);
      ref.invalidate(readingSessionsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).restoreCompleted(report.books, report.files),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).failure('恢复', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: AppStrings.of(context).text('选择 Leeef 同步目录'),
    );
    if (path == null || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_syncDirectoryKey, path);
    setState(() => _syncDirectory = path);
  }

  Future<void> _configureWebDav() async {
    final urlController = TextEditingController(text: _webDavUrl);
    final usernameController = TextEditingController(text: _webDavUsername);
    final passwordController = TextEditingController(
      text: await _secureStorage.read(key: _webDavPasswordKey) ?? '',
    );
    if (!mounted) return;
    final configuration = await showDialog<_WebDavConfiguration>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.of(context).text('配置 WebDAV')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('同步目录 URL'),
                  hintText: 'https://example.com/dav/Leeef',
                ),
              ),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('用户名'),
                ),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).text('密码或应用密码'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).text('取消')),
          ),
          FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(urlController.text.trim());
              if (uri == null ||
                  (uri.scheme != 'http' && uri.scheme != 'https') ||
                  uri.host.isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _WebDavConfiguration(
                  url: uri.toString(),
                  username: usernameController.text.trim(),
                  password: passwordController.text,
                ),
              );
            },
            child: Text(AppStrings.of(context).text('保存')),
          ),
        ],
      ),
    );
    urlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    if (configuration == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_webDavUrlKey, configuration.url);
    await preferences.setString(_webDavUsernameKey, configuration.username);
    await _secureStorage.write(
      key: _webDavPasswordKey,
      value: configuration.password,
    );
    if (mounted) {
      setState(() {
        _webDavUrl = configuration.url;
        _webDavUsername = configuration.username;
      });
    }
  }

  Future<void> _configureS3() async {
    final endpointController = TextEditingController(text: _s3Endpoint);
    final bucketController = TextEditingController(text: _s3Bucket);
    final regionController = TextEditingController(text: _s3Region);
    final prefixController = TextEditingController(text: _s3Prefix);
    final accessKeyController = TextEditingController(
      text: await _secureStorage.read(key: _s3AccessKeyIdKey) ?? '',
    );
    final secretKeyController = TextEditingController(
      text: await _secureStorage.read(key: _s3SecretAccessKeyKey) ?? '',
    );
    final sessionTokenController = TextEditingController(
      text: await _secureStorage.read(key: _s3SessionTokenKey) ?? '',
    );
    var pathStyle = _s3PathStyle;
    if (!mounted) return;
    final configuration = await showDialog<_S3Configuration>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppStrings.of(context).text('配置 S3-compatible')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: endpointController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint',
                      hintText: 'https://s3.example.com',
                    ),
                  ),
                  TextField(
                    controller: bucketController,
                    decoration: const InputDecoration(labelText: 'Bucket'),
                  ),
                  TextField(
                    controller: regionController,
                    decoration: const InputDecoration(labelText: 'Region'),
                  ),
                  TextField(
                    controller: prefixController,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('对象前缀'),
                    ),
                  ),
                  TextField(
                    controller: accessKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Access Key ID',
                    ),
                  ),
                  TextField(
                    controller: secretKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Secret Access Key',
                    ),
                  ),
                  TextField(
                    controller: sessionTokenController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(
                        context,
                      ).text('Session Token（可选）'),
                    ),
                  ),
                  SwitchListTile(
                    value: pathStyle,
                    title: Text(AppStrings.of(context).text('Path-style 请求')),
                    subtitle: Text(
                      AppStrings.of(context).text('MinIO、NAS 等兼容服务通常需要开启'),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => pathStyle = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).text('取消')),
            ),
            FilledButton(
              onPressed: () {
                final endpoint = Uri.tryParse(endpointController.text.trim());
                if (endpoint == null ||
                    (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
                    endpoint.host.isEmpty ||
                    bucketController.text.trim().isEmpty ||
                    regionController.text.trim().isEmpty ||
                    accessKeyController.text.trim().isEmpty ||
                    secretKeyController.text.isEmpty) {
                  return;
                }
                Navigator.pop(
                  context,
                  _S3Configuration(
                    endpoint: endpoint.toString(),
                    bucket: bucketController.text.trim(),
                    region: regionController.text.trim(),
                    prefix: prefixController.text.trim(),
                    pathStyle: pathStyle,
                    accessKeyId: accessKeyController.text.trim(),
                    secretAccessKey: secretKeyController.text,
                    sessionToken: sessionTokenController.text.trim(),
                  ),
                );
              },
              child: Text(AppStrings.of(context).text('保存')),
            ),
          ],
        ),
      ),
    );
    endpointController.dispose();
    bucketController.dispose();
    regionController.dispose();
    prefixController.dispose();
    accessKeyController.dispose();
    secretKeyController.dispose();
    sessionTokenController.dispose();
    if (configuration == null) return;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_s3EndpointKey, configuration.endpoint),
      preferences.setString(_s3BucketKey, configuration.bucket),
      preferences.setString(_s3RegionKey, configuration.region),
      preferences.setString(_s3PrefixKey, configuration.prefix),
      preferences.setBool(_s3PathStyleKey, configuration.pathStyle),
      _secureStorage.write(
        key: _s3AccessKeyIdKey,
        value: configuration.accessKeyId,
      ),
      _secureStorage.write(
        key: _s3SecretAccessKeyKey,
        value: configuration.secretAccessKey,
      ),
      _secureStorage.write(
        key: _s3SessionTokenKey,
        value: configuration.sessionToken,
      ),
    ]);
    if (mounted) {
      setState(() {
        _s3Endpoint = configuration.endpoint;
        _s3Bucket = configuration.bucket;
        _s3Region = configuration.region;
        _s3Prefix = configuration.prefix;
        _s3PathStyle = configuration.pathStyle;
      });
    }
  }

  Future<SyncBackend> _buildSyncBackend() async {
    switch (_syncBackend) {
      case _SyncBackendKind.s3:
        final endpoint = _s3Endpoint;
        final bucket = _s3Bucket;
        if (endpoint == null || bucket == null) {
          throw StateError('请先配置 S3-compatible。');
        }
        final accessKeyId =
            await _secureStorage.read(key: _s3AccessKeyIdKey) ?? '';
        final secretAccessKey =
            await _secureStorage.read(key: _s3SecretAccessKeyKey) ?? '';
        return S3SyncBackend(
          endpoint: Uri.parse(endpoint),
          bucket: bucket,
          region: _s3Region,
          prefix: _s3Prefix,
          pathStyle: _s3PathStyle,
          accessKeyId: accessKeyId,
          secretAccessKey: secretAccessKey,
          sessionToken: await _secureStorage.read(key: _s3SessionTokenKey),
        );
      case _SyncBackendKind.directory:
        final path = _syncDirectory;
        if (path == null) throw StateError('请先选择同步目录。');
        return DirectorySyncBackend(Directory(path));
      case _SyncBackendKind.webDav:
        final url = _webDavUrl;
        if (url == null) throw StateError('请先配置 WebDAV。');
        return WebDavSyncBackend(
          root: Uri.parse(url),
          username: _webDavUsername,
          password: await _secureStorage.read(key: _webDavPasswordKey),
        );
    }
  }

  Future<void> _testBackendCapabilities() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final backend = await _buildSyncBackend();
      if (backend is S3SyncBackend) await backend.verifyCapabilities();
      if (backend is WebDavSyncBackend) await backend.verifyCapabilities();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).text('同步后端连接和读写能力正常'))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).failure('同步后端检测', error)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _synchronize() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final engine = SyncEngine(
        repository: await ref.read(libraryRepositoryProvider.future),
        backend: await _buildSyncBackend(),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
        trustedSyncService: await loadTrustedSyncService(),
      );
      final report = await engine.synchronize();
      if ((report.trustedSync?.appliedConfigurationValues ?? 0) > 0) {
        await AppAppearanceController.instance.load();
      }
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(allExcerptsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：上传 ${report.uploadedOperations}，接收 ${report.downloadedOperations}，下载书籍 ${report.downloadedBooks}、封面 ${report.downloadedCovers}，配置 ${report.trustedSync?.appliedConfigurationValues ?? 0} 项',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.of(context).failure('同步', error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadCloudBooks() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(libraryRepositoryProvider.future);
      final books = (await repository.listBooks())
          .where((book) => !book.isAvailableLocally)
          .toList();
      if (books.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.of(context).text('没有需要下载的云端书籍'))),
          );
        }
        return;
      }
      final engine = SyncEngine(
        repository: repository,
        backend: await _buildSyncBackend(),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      );
      var downloaded = 0;
      var unavailable = 0;
      final failures = <String>[];
      for (final book in books) {
        try {
          if (await engine.downloadBook(book.id)) {
            downloaded++;
          } else {
            unavailable++;
          }
        } on Object catch (error) {
          failures.add('${book.title}: $error');
        }
      }
      ref.invalidate(libraryBooksProvider);
      await _refreshStorage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '批量下载完成：成功 $downloaded，本后端缺失 $unavailable，失败 ${failures.length}'
            '${failures.isEmpty ? '' : '；${failures.first}'}',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).failure('批量下载', error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(strings.text('界面语言')),
          trailing: DropdownButton<String>(
            value: _locale,
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text(strings.text('跟随系统')),
              ),
              DropdownMenuItem(value: 'zh', child: Text(strings.text('简体中文'))),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(
                value: 'ja',
                child: Text(AppStrings.of(context).text('日本語')),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              await AppAppearanceController.instance.setLocale(value);
              if (mounted) setState(() => _locale = value);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: Text(strings.text('明暗主题')),
          trailing: DropdownButton<ThemeMode>(
            value: _themeMode,
            items: [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text(strings.text('跟随系统')),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text(strings.text('浅色')),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text(strings.text('深色')),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              await AppAppearanceController.instance.setThemeMode(value);
              if (mounted) setState(() => _themeMode = value);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(strings.text('主题色')),
          subtitle: Wrap(
            spacing: 8,
            children: [
              for (final entry in const [
                (Color(0xFF356A45), '叶绿'),
                (Color(0xFF4469A8), '蓝色'),
                (Color(0xFF8A4F7D), '紫色'),
                (Color(0xFF9A5C22), '棕色'),
                (Color(0xFF546E7A), '灰蓝'),
              ])
                Semantics(
                  label: strings.text(entry.$2),
                  selected: _seedColor.toARGB32() == entry.$1.toARGB32(),
                  child: ChoiceChip(
                    label: const SizedBox(width: 18, height: 18),
                    avatar: CircleAvatar(backgroundColor: entry.$1),
                    selected: _seedColor.toARGB32() == entry.$1.toARGB32(),
                    onSelected: (_) async {
                      await AppAppearanceController.instance.setSeedColor(
                        entry.$1,
                      );
                      if (mounted) setState(() => _seedColor = entry.$1);
                    },
                  ),
                ),
            ],
          ),
        ),
        ExpansionTile(
          leading: const Icon(Icons.view_quilt_outlined),
          title: Text(strings.text('导航与书架外观')),
          children: [
            for (final section in const [
              (_AppSection.notes, '笔记'),
              (_AppSection.search, '搜索'),
              (_AppSection.statistics, '统计'),
            ])
              SwitchListTile(
                title: Text(
                  '${strings.text('显示')}${strings.text(section.$2)}${strings.text('栏目')}',
                ),
                value: AppAppearanceController.instance.visibleNavigation
                    .contains(section.$1.name),
                onChanged: (value) async {
                  await AppAppearanceController.instance.setNavigationVisible(
                    section.$1.name,
                    value,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ListTile(
              title: Text(strings.text('书架密度')),
              trailing: DropdownButton<String>(
                value: AppAppearanceController.instance.shelfStyle,
                items: [
                  DropdownMenuItem(
                    value: 'comfortable',
                    child: Text(strings.text('舒适封面')),
                  ),
                  DropdownMenuItem(
                    value: 'compact',
                    child: Text(strings.text('紧凑封面')),
                  ),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  await AppAppearanceController.instance.setShelfStyle(value);
                  if (mounted) setState(() {});
                },
              ),
            ),
            ListTile(
              title: Text(strings.text('封面填充')),
              trailing: SegmentedButton<BoxFit>(
                segments: [
                  ButtonSegment(
                    value: BoxFit.cover,
                    label: Text(strings.text('裁切')),
                  ),
                  ButtonSegment(
                    value: BoxFit.contain,
                    label: Text(strings.text('完整')),
                  ),
                ],
                selected: {AppAppearanceController.instance.coverFit},
                onSelectionChanged: (value) async {
                  await AppAppearanceController.instance.setCoverFit(
                    value.single,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
        ListTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(strings.text('检查更新与变更日志')),
          subtitle: Text(strings.text('从 GitHub Releases 获取最新版本和发布说明')),
          trailing: TextButton(
            onPressed: _busy ? null : _checkForUpdates,
            child: Text(strings.text('检查')),
          ),
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.sync_lock),
          title: Text(strings.text('自动同步')),
          subtitle: Text(strings.text('网络恢复、应用回到前台及定时触发时同步')),
          value: _autoSync,
          onChanged: _busy ? null : _setAutoSync,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.wifi),
          title: Text(strings.text('仅 Wi-Fi / 有线网络')),
          subtitle: Text(strings.text('开启后不会通过移动数据自动同步')),
          value: _wifiOnly,
          onChanged: !_autoSync || _busy ? null : _setWifiOnly,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(strings.text('同步完成通知')),
          subtitle: Text(strings.text('后台同步结束后显示系统通知')),
          value: _syncNotifications,
          onChanged: (value) async {
            await (await SharedPreferences.getInstance()).setBool(
              'leeef.sync.completion_notifications',
              value,
            );
            if (value) await AppNotifications.requestPermissions();
            if (mounted) setState(() => _syncNotifications = value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.lan_outlined),
          title: Text(strings.text('HTTP/HTTPS 代理')),
          subtitle: Text(
            _proxyHost == null
                ? strings.text('未启用')
                : '$_proxyHost:${_proxyPort ?? ''}',
          ),
          trailing: TextButton(
            onPressed: _busy ? null : _configureProxy,
            child: Text(strings.text('配置')),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text(strings.text('AI 上下文翻译')),
          subtitle: Text(
            _aiBaseUrl == null
                ? strings.text('尚未配置')
                : '${_aiModel ?? ''}\n${_aiBaseUrl ?? ''}',
          ),
          isThreeLine: _aiBaseUrl != null,
          trailing: TextButton(
            onPressed: _busy ? null : _configureAi,
            child: Text(strings.text('配置')),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: Text(strings.text('AI 阅读助手')),
          subtitle: Text(strings.text('对话查询书库、总结、回顾、分析和生成思维导图')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AiAssistantScreen()),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(strings.text('AI Provider、Prompt 与 Tools')),
          subtitle: Text(
            strings.text('Claude/Gemini 原生协议、推理强度、助手 Prompt 和上下文工具开关'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _configureAiAdvanced,
        ),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: Text(strings.text('AI Prompt 管理')),
          subtitle: Text(strings.text('编辑内置 Prompt，添加或删除用户 Prompt')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const AiPromptManagerScreen(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(strings.text('检测 AI 模型')),
          subtitle: Text(strings.text('发送最小翻译请求，验证 API、模型和密钥')),
          trailing: TextButton(
            onPressed: _busy || _aiBaseUrl == null ? null : _testAi,
            child: Text(strings.text('检测')),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.record_voice_over_outlined),
          title: Text(strings.text('TTS 朗读服务')),
          subtitle: Text(
            strings.text(switch (_ttsService) {
              TtsService.system => '系统 TTS',
              TtsService.openAi => 'OpenAI TTS',
              TtsService.azure => 'Azure Speech',
              TtsService.alibaba => '阿里云智能语音',
            }),
          ),
          trailing: TextButton(
            onPressed: _busy ? null : _configureTts,
            child: Text(strings.text('配置')),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(strings.text('完整备份')),
          subtitle: Text(strings.text('导出数据库、操作日志、书籍和封面，并附带 SHA-256 完整性信息')),
          trailing: TextButton(
            onPressed: _busy ? null : _exportBackup,
            child: Text(strings.text('导出')),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(strings.text('恢复备份')),
          subtitle: Text(strings.text('先校验、再原子恢复；恢复的操作日志会重新参与同步')),
          trailing: TextButton(
            onPressed: _busy ? null : _restoreBackup,
            child: Text(strings.text('恢复')),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(strings.text('存储统计与文件检查')),
          subtitle: Text(
            _storageReport == null
                ? strings.text('正在检查…')
                : strings.storageSummary(
                    bookBytes: _formatBytes(_storageReport!.bookBytes),
                    coverBytes: _formatBytes(_storageReport!.coverBytes),
                    orphanBytes: _formatBytes(_storageReport!.orphanBytes),
                    localBooks: _storageReport!.localBooks,
                    missingBooks: _storageReport!.missingBooks.length,
                    md5Missing: _storageReport!.md5Missing,
                  ),
          ),
          isThreeLine: true,
          trailing: IconButton(
            onPressed: _busy ? null : _refreshStorage,
            icon: const Icon(Icons.refresh),
            tooltip: strings.text('重新检查'),
          ),
          onTap: _showStorageDetails,
        ),
        ListTile(
          leading: const Icon(Icons.font_download_outlined),
          title: Text(strings.text('阅读字体管理')),
          subtitle: Text(strings.text('导入、替换或删除流式阅读器共用字体，并查看缓存占用')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _manageFonts,
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_move_outline),
          title: Text(strings.text('自定义书籍数据目录')),
          subtitle: Text(_customDirectory ?? strings.text('使用应用默认目录')),
          trailing: TextButton(
            onPressed: _busy ? null : _chooseDataDirectory,
            child: Text(strings.text('迁移')),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _runMaintenance(
                      (service) => service.backfillMd5(),
                      '已补算 MD5 本数',
                    ),
              icon: const Icon(Icons.fingerprint),
              label: Text(strings.text('补算 MD5')),
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _runMaintenance(
                      (service) => service.repairMissingFileFlags(),
                      '已修复缺失文件状态',
                    ),
              icon: const Icon(Icons.find_in_page_outlined),
              label: Text(strings.text('修复缺失状态')),
            ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _runMaintenance(
                      (service) => service.clearOrphanFiles(),
                      '已清理字节数',
                    ),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(strings.text('清理孤立缓存')),
            ),
          ],
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.code_outlined),
          title: Text(strings.text('EPUB JavaScript')),
          subtitle: Text(strings.text('仅对信任的互动书籍开启；关闭可减少脚本风险')),
          value: _epubJavaScript,
          onChanged: (value) async {
            await (await SharedPreferences.getInstance()).setBool(
              'leeef.reader.epub_javascript',
              value,
            );
            if (mounted) setState(() => _epubJavaScript = value);
          },
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Text(strings.text('重置新手引导与提示')),
          subtitle: Text(strings.text('下次启动时重新显示功能引导')),
          trailing: TextButton(
            onPressed: _resetOnboardingAndTips,
            child: Text(strings.text('重置')),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.developer_mode),
          title: Text(strings.text('开发者选项')),
          subtitle: Text(strings.text('显示诊断日志和运行时信息')),
          value: _developerMode,
          onChanged: (value) async {
            await (await SharedPreferences.getInstance()).setBool(
              'leeef.developer.enabled',
              value,
            );
            if (mounted) setState(() => _developerMode = value);
          },
        ),
        if (_developerMode)
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(strings.text('查看应用日志')),
            subtitle: Text(strings.text('日志自动滚动保留最近约 1 MB，可复制或清空')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showLogs,
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(strings.text('OPDS 目录')),
          subtitle: Text(strings.text('管理自定义目录，浏览、搜索、下载并导入电子书')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const OpdsScreen()),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.devices_other),
          title: Text(strings.text('我的同步设备')),
          subtitle: Text(strings.text('配对新设备，自动迁移配置、凭据和书库数据')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const TrustedDevicesScreen(),
              ),
            );
            await _loadSettingsPreferences();
          },
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(strings.text('同步方式')),
          trailing: DropdownButton<_SyncBackendKind>(
            value: _syncBackend,
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _setBackend(value);
                  },
            items: [
              DropdownMenuItem(
                value: _SyncBackendKind.s3,
                child: Text('S3-compatible'),
              ),
              DropdownMenuItem(
                value: _SyncBackendKind.directory,
                child: Text(strings.text('共享目录')),
              ),
              DropdownMenuItem(
                value: _SyncBackendKind.webDav,
                child: Text('WebDAV'),
              ),
            ],
          ),
        ),
        if (_syncBackend == _SyncBackendKind.s3)
          ListTile(
            leading: const Icon(Icons.cloud_queue),
            title: Text(strings.text('S3-compatible 对象存储')),
            subtitle: Text(
              _s3Endpoint == null
                  ? strings.text('尚未配置')
                  : '${_s3Endpoint!}\n${_s3Bucket ?? ''} / $_s3Prefix',
            ),
            isThreeLine: _s3Endpoint != null,
            trailing: TextButton(
              onPressed: _busy ? null : _configureS3,
              child: Text(strings.text('配置')),
            ),
          ),
        if (_syncBackend == _SyncBackendKind.s3)
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(strings.text('检测 S3 能力')),
            subtitle: Text(strings.text('验证签名、条件写入、上传、下载、列举和删除')),
            trailing: TextButton(
              onPressed: _busy || _s3Endpoint == null
                  ? null
                  : _testBackendCapabilities,
              child: Text(strings.text('检测')),
            ),
          ),
        if (_syncBackend == _SyncBackendKind.directory)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(strings.text('同步目录')),
            subtitle: Text(_syncDirectory ?? strings.text('尚未选择，可使用共享目录或网络盘')),
            trailing: TextButton(
              onPressed: _busy ? null : _chooseDirectory,
              child: Text(strings.text('选择')),
            ),
          ),
        if (_syncBackend == _SyncBackendKind.webDav)
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(strings.text('WebDAV 服务器')),
            subtitle: Text(
              _webDavUrl == null
                  ? strings.text('尚未配置')
                  : '${_webDavUrl!}\n${_webDavUsername?.isEmpty ?? true ? strings.text('匿名访问') : _webDavUsername}',
            ),
            isThreeLine: _webDavUrl != null,
            trailing: TextButton(
              onPressed: _busy ? null : _configureWebDav,
              child: Text(strings.text('配置')),
            ),
          ),
        if (_syncBackend == _SyncBackendKind.webDav)
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(strings.text('检测 WebDAV 能力')),
            subtitle: Text(strings.text('验证目录、上传、下载、条件写入、列举和删除')),
            trailing: TextButton(
              onPressed: _busy || _webDavUrl == null
                  ? null
                  : _testBackendCapabilities,
              child: Text(strings.text('检测')),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(strings.text('立即同步')),
          subtitle: Text(strings.text('离线失败不会丢失变更，恢复连接后可安全重试')),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed:
                      (_syncBackend == _SyncBackendKind.directory &&
                              _syncDirectory == null) ||
                          (_syncBackend == _SyncBackendKind.s3 &&
                              _s3Endpoint == null) ||
                          (_syncBackend == _SyncBackendKind.webDav &&
                              _webDavUrl == null)
                      ? null
                      : _synchronize,
                  child: Text(strings.text('同步')),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_download_outlined),
          title: Text(strings.text('批量下载云端书籍')),
          subtitle: Text(strings.text('下载所有仅保留在同步后端、当前设备尚无副本的书籍')),
          trailing: FilledButton.tonal(
            onPressed:
                _busy ||
                    (_syncBackend == _SyncBackendKind.directory &&
                        _syncDirectory == null) ||
                    (_syncBackend == _SyncBackendKind.s3 &&
                        _s3Endpoint == null) ||
                    (_syncBackend == _SyncBackendKind.webDav &&
                        _webDavUrl == null)
                ? null
                : _downloadCloudBooks,
            child: Text(strings.text('全部下载')),
          ),
        ),
      ],
    );
  }
}

enum _SyncBackendKind { s3, directory, webDav }

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _WebDavConfiguration {
  const _WebDavConfiguration({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;
}

class _S3Configuration {
  const _S3Configuration({
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.prefix,
    required this.pathStyle,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
  });

  final String endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final bool pathStyle;
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      strings.text('开始你的书库'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.text(
                        '导入 EPUB、MOBI、AZW3、FB2、PDF 或 TXT。阅读进度和书摘会先保存在本地，联网后再安全同步。',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
