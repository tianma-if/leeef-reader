import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/reader/reader_page_turn_policy.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/reader/reader_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderSidebarTab { toc, annotations, bookmarks }

const readerSidebarWidth = 280.0;

class ReaderSidebarTocItem {
  const ReaderSidebarTocItem({
    required this.id,
    required this.label,
    this.pageLabel,
    this.depth = 0,
  });

  final String id;
  final String label;
  final String? pageLabel;
  final int depth;
}

class ReaderSidebarPin {
  static const preferenceKey = 'leeef.reader.sidebar_pinned';

  static Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(preferenceKey) ?? isDesktopReaderPlatform();
  }

  static Future<void> save(bool pinned) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, pinned);
  }
}

List<ReaderSidebarTocItem> flattenReaderToc(
  List<ReaderTocItem> items, {
  int depth = 0,
}) {
  final result = <ReaderSidebarTocItem>[];
  for (final item in items) {
    result.add(
      ReaderSidebarTocItem(id: item.href, label: item.label, depth: depth),
    );
    result.addAll(flattenReaderToc(item.children, depth: depth + 1));
  }
  return result;
}

String? matchingTocId(List<ReaderSidebarTocItem> toc, String? chapterTitle) {
  if (chapterTitle == null) return null;
  final needle = chapterTitle.trim();
  if (needle.isEmpty) return null;
  for (final item in toc.reversed) {
    if (item.label == needle) return item.id;
  }
  for (final item in toc.reversed) {
    if (item.label.isNotEmpty &&
        (needle.contains(item.label) || item.label.contains(needle))) {
      return item.id;
    }
  }
  return null;
}

String? matchingTocIdByPage(List<ReaderSidebarTocItem> toc, int page) {
  ReaderSidebarTocItem? current;
  for (final item in toc) {
    final number = int.tryParse(item.pageLabel ?? '');
    if (number != null && number <= page) current = item;
  }
  return current?.id;
}

String readerPageFractionLabel({int? current, int? total, double? progress}) {
  if (current != null && total != null && total > 0) {
    return '$current / $total';
  }
  if (progress != null) return '${(progress.clamp(0, 1) * 100).round()}%';
  return '';
}

sealed class ReaderTocDisplayRow {
  const ReaderTocDisplayRow();
}

class ReaderTocEntryRow extends ReaderTocDisplayRow {
  const ReaderTocEntryRow(this.item);
  final ReaderSidebarTocItem item;
}

class ReaderTocCurrentRow extends ReaderTocDisplayRow {
  const ReaderTocCurrentRow(this.pageLabel);
  final String? pageLabel;
}

List<ReaderTocDisplayRow> readerTocDisplayRows({
  required List<ReaderSidebarTocItem> toc,
  String? currentTocId,
  String? currentPageLabel,
}) {
  final rows = <ReaderTocDisplayRow>[];
  var insertedCurrent = false;
  for (final item in toc) {
    rows.add(ReaderTocEntryRow(item));
    if (item.id == currentTocId) {
      rows.add(ReaderTocCurrentRow(currentPageLabel));
      insertedCurrent = true;
    }
  }
  if (!insertedCurrent) {
    rows.insert(0, ReaderTocCurrentRow(currentPageLabel));
  }
  return rows;
}

class ReaderSidebar extends ConsumerWidget {
  const ReaderSidebar({
    required this.bookId,
    required this.bookTitle,
    required this.toc,
    required this.tab,
    required this.onTabChanged,
    required this.onOpenToc,
    required this.onOpenLocator,
    super.key,
    this.bookAuthor,
    this.coverPath,
    this.currentTocId,
    this.currentPageLabel,
    this.pinned = false,
    this.onTogglePin,
    this.onClose,
    this.onSearch,
    this.onShowBookInfo,
    this.onReadingSettings,
    this.onTts,
    this.onAddBookmark,
  });

  final String bookId;
  final String bookTitle;
  final String? bookAuthor;
  final String? coverPath;
  final List<ReaderSidebarTocItem> toc;
  final String? currentTocId;
  final String? currentPageLabel;
  final ReaderSidebarTab tab;
  final ValueChanged<ReaderSidebarTab> onTabChanged;
  final ValueChanged<ReaderSidebarTocItem> onOpenToc;
  final ValueChanged<String> onOpenLocator;
  final bool pinned;
  final VoidCallback? onTogglePin;
  final VoidCallback? onClose;
  final VoidCallback? onSearch;
  final VoidCallback? onShowBookInfo;
  final VoidCallback? onReadingSettings;
  final VoidCallback? onTts;
  final VoidCallback? onAddBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final excerpts = tab == ReaderSidebarTab.annotations
        ? ref.watch(bookExcerptsProvider(bookId)).asData?.value ?? const []
        : const <ExcerptRecord>[];
    final bookmarks = tab == ReaderSidebarTab.bookmarks
        ? ref.watch(bookBookmarksProvider(bookId)).asData?.value ?? const []
        : const <BookmarkRecord>[];
    final desktop = isDesktopReaderPlatform();
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: desktop ? Clip.hardEdge : Clip.antiAlias,
      shape: desktop
          ? null
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
      child: SafeArea(
        top: desktop,
        right: desktop,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!desktop) _SidebarDragHandle(onClose: onClose),
            _SidebarHeader(
              pinned: pinned,
              desktop: desktop,
              onClose: onClose,
              onSearch: onSearch,
              onTogglePin: onTogglePin,
              onReadingSettings: onReadingSettings,
              onTts: onTts,
              onAddBookmark: onAddBookmark,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: _BookTitleRow(
                title: bookTitle,
                author: bookAuthor,
                coverPath: coverPath,
                onInfo: onShowBookInfo,
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              child: switch (tab) {
                ReaderSidebarTab.toc => _TocList(
                  toc: toc,
                  currentTocId: currentTocId,
                  currentPageLabel: currentPageLabel,
                  onOpenToc: onOpenToc,
                ),
                ReaderSidebarTab.annotations => _ExcerptList(
                  excerpts: excerpts,
                  onOpen: onOpenLocator,
                  onDelete: (id) => unawaited(_deleteExcerpt(ref, id)),
                ),
                ReaderSidebarTab.bookmarks => _BookmarkList(
                  bookmarks: bookmarks,
                  onOpen: onOpenLocator,
                  onDelete: (id) => unawaited(_deleteBookmark(ref, id)),
                ),
              },
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            _SidebarTabs(tab: tab, onTabChanged: onTabChanged),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExcerpt(WidgetRef ref, String id) async {
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.deleteExcerpt(id);
  }

  Future<void> _deleteBookmark(WidgetRef ref, String id) async {
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.deleteBookmark(id);
  }
}

class _SidebarDragHandle extends StatelessWidget {
  const _SidebarDragHandle({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 240) onClose?.call();
      },
      child: SizedBox(
        height: 28,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
            child: const SizedBox(width: 40, height: 4),
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.pinned,
    required this.desktop,
    this.onClose,
    this.onSearch,
    this.onTogglePin,
    this.onReadingSettings,
    this.onTts,
    this.onAddBookmark,
  });

  final bool pinned;
  final bool desktop;
  final VoidCallback? onClose;
  final VoidCallback? onSearch;
  final VoidCallback? onTogglePin;
  final VoidCallback? onReadingSettings;
  final VoidCallback? onTts;
  final VoidCallback? onAddBookmark;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            if (!desktop)
              IconButton(
                tooltip: strings.text('关闭侧栏'),
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              )
            else
              IconButton(
                tooltip: pinned ? strings.text('关闭侧栏') : strings.text('打开侧栏'),
                onPressed: onClose,
                icon: const Icon(Icons.view_sidebar_outlined, size: 20),
              ),
            const Spacer(),
            IconButton(
              tooltip: strings.text('书内搜索'),
              onPressed: onSearch,
              icon: const Icon(Icons.search, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: strings.text('书籍菜单'),
              icon: const Icon(Icons.menu, size: 20),
              onSelected: (value) => switch (value) {
                'search' => onSearch?.call(),
                'style' => onReadingSettings?.call(),
                'tts' => onTts?.call(),
                'bookmark' => onAddBookmark?.call(),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'search',
                  child: Text(strings.text('书内搜索')),
                ),
                PopupMenuItem(
                  value: 'style',
                  child: Text(strings.text('阅读样式')),
                ),
                if (onTts != null)
                  PopupMenuItem(value: 'tts', child: Text(strings.text('朗读'))),
                PopupMenuItem(
                  value: 'bookmark',
                  child: Text(strings.text('添加书签')),
                ),
              ],
            ),
            if (desktop)
              IconButton(
                tooltip: pinned ? strings.text('取消固定侧栏') : strings.text('固定侧栏'),
                onPressed: onTogglePin,
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                ),
                style: pinned
                    ? IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _BookTitleRow extends StatelessWidget {
  const _BookTitleRow({
    required this.title,
    this.author,
    this.coverPath,
    this.onInfo,
  });

  final String title;
  final String? author;
  final String? coverPath;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final path = coverPath;
    return Row(
      children: [
        if (path != null && path.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.file(
              File(path),
              width: 28,
              height: 40,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => const SizedBox(width: 28, height: 40),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (author != null && author!.trim().isNotEmpty)
                Text(
                  author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: strings.text('书籍信息'),
          onPressed: onInfo,
          icon: const Icon(Icons.info_outline, size: 18),
        ),
      ],
    );
  }
}

class _TocList extends StatelessWidget {
  const _TocList({
    required this.toc,
    required this.onOpenToc,
    this.currentTocId,
    this.currentPageLabel,
  });

  final List<ReaderSidebarTocItem> toc;
  final String? currentTocId;
  final String? currentPageLabel;
  final ValueChanged<ReaderSidebarTocItem> onOpenToc;

  @override
  Widget build(BuildContext context) {
    if (toc.isEmpty && currentPageLabel == null) {
      return const SizedBox.shrink();
    }
    final rows = readerTocDisplayRows(
      toc: toc,
      currentTocId: currentTocId,
      currentPageLabel: currentPageLabel,
    );
    return ListView.builder(
      key: const Key('reader-sidebar-toc'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          ReaderTocEntryRow(:final item) => RepaintBoundary(
            child: _TocRow(
              key: ValueKey(item.id),
              item: item,
              onTap: () => onOpenToc(item),
            ),
          ),
          ReaderTocCurrentRow(:final pageLabel) => _CurrentPositionRow(
            pageLabel: pageLabel,
          ),
        };
      },
    );
  }
}

class _TocRow extends StatelessWidget {
  const _TocRow({required this.item, required this.onTap, super.key});

  final ReaderSidebarTocItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = !isDesktopReaderPlatform();
    final vertical = mobile ? 16.0 : 10.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12 + item.depth * 12,
          vertical,
          16,
          vertical,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(item.label, style: theme.textTheme.bodyMedium),
            ),
            if (item.pageLabel != null && item.pageLabel!.isNotEmpty)
              Text(
                item.pageLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPositionRow extends StatelessWidget {
  const _CurrentPositionRow({this.pageLabel});

  final String? pageLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: DecoratedBox(
        key: const Key('reader-current-position'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.85,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.text('当前位置'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (pageLabel != null && pageLabel!.isNotEmpty)
                Text(
                  pageLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExcerptList extends StatelessWidget {
  const _ExcerptList({
    required this.excerpts,
    required this.onOpen,
    required this.onDelete,
  });

  final List<ExcerptRecord> excerpts;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (excerpts.isEmpty) {
      return Center(child: Text(strings.text('没有书摘')));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: excerpts.length,
      itemBuilder: (context, index) {
        final excerpt = excerpts[index];
        return ListTile(
          title: Text(
            excerpt.quote,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: excerpt.note == null || excerpt.note!.isEmpty
              ? null
              : Text(excerpt.note!, maxLines: 2),
          onTap: () => onOpen(excerpt.locator),
          onLongPress: () => onDelete(excerpt.id),
        );
      },
    );
  }
}

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.onOpen,
    required this.onDelete,
  });

  final List<BookmarkRecord> bookmarks;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (bookmarks.isEmpty) {
      return Center(child: Text(strings.text('没有书签')));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        return ListTile(
          leading: const Icon(Icons.bookmark_border),
          title: Text(
            bookmark.title?.trim().isNotEmpty == true
                ? bookmark.title!
                : strings.text('未命名书签'),
          ),
          onTap: () => onOpen(bookmark.locator),
          onLongPress: () => onDelete(bookmark.id),
        );
      },
    );
  }
}

class _SidebarTabs extends StatelessWidget {
  const _SidebarTabs({required this.tab, required this.onTabChanged});

  final ReaderSidebarTab tab;
  final ValueChanged<ReaderSidebarTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          _TabButton(
            icon: Icons.list,
            label: strings.text('目录'),
            selected: tab == ReaderSidebarTab.toc,
            onPressed: () => onTabChanged(ReaderSidebarTab.toc),
          ),
          _TabButton(
            icon: Icons.edit_outlined,
            label: strings.text('批注'),
            selected: tab == ReaderSidebarTab.annotations,
            onPressed: () => onTabChanged(ReaderSidebarTab.annotations),
          ),
          _TabButton(
            icon: Icons.bookmark_border,
            label: strings.text('书签'),
            selected: tab == ReaderSidebarTab.bookmarks,
            onPressed: () => onTabChanged(ReaderSidebarTab.bookmarks),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 36,
              child: Icon(icon, size: 20, semanticLabel: label),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showReaderBookInfoDialog({
  required BuildContext context,
  required String title,
  String? author,
  String? description,
}) {
  final strings = AppStrings.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.text('书籍信息')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (author != null && author.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(author),
          ],
          if (description != null && description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.text('关闭')),
        ),
      ],
    ),
  );
}
