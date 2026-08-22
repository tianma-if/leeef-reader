import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/reader/reader_screen.dart';
import 'package:leeef_reader/src/sync/directory_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _selectedIndex = 0;
  bool _isImporting = false;

  Future<void> _importBook() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    final path = result?.path;
    if (path == null || !mounted) return;
    setState(() => _isImporting = true);
    try {
      final importer = await ref.read(bookImportServiceProvider.future);
      final book = await importer.importFile(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入《${book.title}》')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        final title = switch (_selectedIndex) {
          0 => '书库',
          1 => '笔记',
          _ => '设置',
        };
        final content = switch (_selectedIndex) {
          0 => const _LibraryContent(),
          1 => const _ExcerptContent(),
          _ => const _SettingsContent(),
        };
        final importButton = _selectedIndex == 0
            ? FloatingActionButton.extended(
                onPressed: _isImporting ? null : _importBook,
                icon: _isImporting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(_isImporting ? '导入中' : '导入书籍'),
              )
            : null;

        if (!useRail) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: content,
            floatingActionButton: importButton,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: _destinations,
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                labelType: NavigationRailLabelType.all,
                destinations: _railDestinations,
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
        );
      },
    );
  }
}

const _destinations = [
  NavigationDestination(
    icon: Icon(Icons.local_library_outlined),
    selectedIcon: Icon(Icons.local_library),
    label: '书库',
  ),
  NavigationDestination(icon: Icon(Icons.edit_note_outlined), label: '笔记'),
  NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
];

const _railDestinations = [
  NavigationRailDestination(
    icon: Icon(Icons.local_library_outlined),
    selectedIcon: Icon(Icons.local_library),
    label: Text('书库'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.edit_note_outlined),
    label: Text('笔记'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.settings_outlined),
    label: Text('设置'),
  ),
];

class _LibraryContent extends ConsumerWidget {
  const _LibraryContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryBooksProvider);
    return books.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法读取书库：$error')),
      data: (items) => items.isEmpty
          ? const _EmptyLibrary()
          : GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: 250,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _BookCard(book: items[index]),
            ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book});

  final BookRecord book;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
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
                book.author ?? '未知作者',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExcerptContent extends ConsumerWidget {
  const _ExcerptContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excerpts = ref.watch(allExcerptsProvider);
    return excerpts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('无法读取书摘：$error')),
      data: (items) => items.isEmpty
          ? const Center(child: Text('选中书中文字，即可创建第一条书摘。'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final excerpt = items[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.format_quote),
                    title: Text(excerpt.quote),
                    subtitle: excerpt.note == null ? null : Text(excerpt.note!),
                  ),
                );
              },
            ),
    );
  }
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent();

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  static const _syncDirectoryKey = 'leeef.sync.directory';
  String? _syncDirectory;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (mounted) {
        setState(
          () => _syncDirectory = preferences.getString(_syncDirectoryKey),
        );
      }
    });
  }

  Future<void> _chooseDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 Leeef 同步目录',
    );
    if (path == null || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_syncDirectoryKey, path);
    setState(() => _syncDirectory = path);
  }

  Future<void> _synchronize() async {
    final path = _syncDirectory;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final engine = SyncEngine(
        repository: await ref.read(libraryRepositoryProvider.future),
        backend: DirectorySyncBackend(Directory(path)),
        libraryDirectory: await ref.read(libraryDirectoryProvider.future),
      );
      final report = await engine.synchronize();
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(allExcerptsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：上传 ${report.uploadedOperations}，接收 ${report.downloadedOperations}，下载书籍 ${report.downloadedBooks}',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败，稍后可重试：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('同步目录'),
          subtitle: Text(_syncDirectory ?? '尚未选择，可使用共享目录或网络盘'),
          trailing: TextButton(
            onPressed: _busy ? null : _chooseDirectory,
            child: const Text('选择'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('立即同步'),
          subtitle: const Text('离线失败不会丢失变更，恢复连接后可安全重试'),
          trailing: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonal(
                  onPressed: _syncDirectory == null ? null : _synchronize,
                  child: const Text('同步'),
                ),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Center(
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
              Text('开始你的书库', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '导入 EPUB。阅读进度和书摘会先保存在本地，联网后再安全同步。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
