import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/reader/reader_screen.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReadingStatisticsScreen extends ConsumerStatefulWidget {
  const ReadingStatisticsScreen({super.key});

  @override
  ConsumerState<ReadingStatisticsScreen> createState() =>
      _ReadingStatisticsScreenState();
}

class _ReadingStatisticsScreenState
    extends ConsumerState<ReadingStatisticsScreen> {
  _StatisticsRange _range = _StatisticsRange.month;
  List<_DashboardCardId> _cardOrder = List.of(_DashboardCardId.values);

  @override
  void initState() {
    super.initState();
    _loadCardOrder();
  }

  Future<void> _loadCardOrder() async {
    final values = await SharedPreferences.getInstance();
    final stored = values.getStringList('leeef.statistics.dashboard_cards');
    if (stored == null) return;
    final restored = stored
        .map(
          (name) => _DashboardCardId.values
              .where((item) => item.name == name)
              .firstOrNull,
        )
        .nonNulls
        .toList();
    if (mounted) setState(() => _cardOrder = restored);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final sessions = ref.watch(readingSessionsProvider);
    final books = ref.watch(libraryBooksProvider);
    final excerpts = ref.watch(allExcerptsProvider);
    final progresses = ref.watch(readingProgressesProvider);
    return sessions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('${strings.text('无法读取统计')}：$error')),
      data: (allSessions) => books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('${strings.text('无法读取统计')}：$error')),
        data: (bookItems) => excerpts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('${strings.text('无法读取统计')}：$error')),
          data: (excerptItems) => progresses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('${strings.text('无法读取统计')}：$error')),
            data: (progressItems) => _buildDashboard(
              context,
              allSessions,
              bookItems,
              excerptItems,
              progressItems,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    List<ReadingSessionRecord> allSessions,
    List<BookRecord> books,
    List<ExcerptRecord> excerpts,
    List<ReadingProgressRecord> progresses,
  ) {
    final strings = AppStrings.of(context);
    final now = DateTime.now();
    final cutoff = switch (_range) {
      _StatisticsRange.week => now.subtract(const Duration(days: 7)),
      _StatisticsRange.month => now.subtract(const Duration(days: 30)),
      _StatisticsRange.year => now.subtract(const Duration(days: 365)),
      _StatisticsRange.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final sessions = allSessions
        .where((session) => session.endedAt.isAfter(cutoff))
        .toList();
    final rangeDuration = now.difference(cutoff);
    final previousCutoff = _range == _StatisticsRange.all
        ? null
        : cutoff.subtract(rangeDuration);
    final previousSeconds = previousCutoff == null
        ? 0
        : allSessions
              .where(
                (session) =>
                    session.endedAt.isAfter(previousCutoff) &&
                    !session.endedAt.isAfter(cutoff),
              )
              .fold<int>(0, (sum, session) => sum + session.durationSeconds);
    final seconds = sessions.fold<int>(
      0,
      (sum, session) => sum + session.durationSeconds,
    );
    final days = sessions.map((session) => _dateKey(session.startedAt)).toSet();
    final byBook = <String, int>{};
    for (final session in sessions) {
      byBook.update(
        session.bookId,
        (value) => value + session.durationSeconds,
        ifAbsent: () => session.durationSeconds,
      );
    }
    final bookById = {for (final book in books) book.id: book};
    final rankedBooks = byBook.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<_StatisticsRange>(
                segments: [
                  ButtonSegment(
                    value: _StatisticsRange.week,
                    label: Text(strings.text('周')),
                  ),
                  ButtonSegment(
                    value: _StatisticsRange.month,
                    label: Text(strings.text('月')),
                  ),
                  ButtonSegment(
                    value: _StatisticsRange.year,
                    label: Text(strings.text('年')),
                  ),
                  ButtonSegment(
                    value: _StatisticsRange.all,
                    label: Text(strings.text('全部')),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: (value) =>
                    setState(() => _range = value.single),
              ),
            ),
            IconButton(
              tooltip: strings.text('管理统计卡片'),
              onPressed: _manageCards,
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in _cardOrder)
              _StatCard(
                key: ValueKey(card),
                label: strings.text(card.label),
                value: switch (card) {
                  _DashboardCardId.duration => strings.duration(seconds),
                  _DashboardCardId.days => strings.daysCount(days.length),
                  _DashboardCardId.streak => strings.daysCount(
                    _streak(allSessions),
                  ),
                  _DashboardCardId.books => strings.booksCount(byBook.length),
                  _DashboardCardId.notes => strings.itemsCount(excerpts.length),
                  _DashboardCardId.week => strings.duration(
                    _secondsSince(
                      allSessions,
                      now.subtract(const Duration(days: 7)),
                    ),
                  ),
                  _DashboardCardId.month => strings.duration(
                    _secondsSince(
                      allSessions,
                      now.subtract(const Duration(days: 30)),
                    ),
                  ),
                  _DashboardCardId.finished => strings.booksCount(
                    progresses.where((item) => item.progress >= .99).length,
                  ),
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          strings.text('近 12 周阅读热力图'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _ReadingHeatmap(sessions: allSessions),
        const SizedBox(height: 20),
        Text(
          strings.text('近 30 日'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _ReadingTrend(sessions: allSessions),
        const SizedBox(height: 20),
        _StageSummaryCard(
          seconds: seconds,
          previousSeconds: previousSeconds,
          finishedBooks: progresses
              .where((item) => item.progress >= .99)
              .length,
          activeBooks: byBook.length,
          notes: excerpts
              .where((item) => item.createdAt.isAfter(cutoff))
              .length,
          comparisonEnabled: previousCutoff != null,
        ),
        if (progresses.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ContinueReadingCard(
            progress:
                (progresses.toList()
                      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
                    .first,
            book:
                bookById[(progresses.toList()
                      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
                    .first
                    .bookId],
          ),
        ],
        if (excerpts.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RandomExcerptCard(
            excerpt: excerpts[DateTime.now().day % excerpts.length],
            book:
                bookById[excerpts[DateTime.now().day % excerpts.length].bookId],
          ),
        ],
        if (rankedBooks.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            strings.text('阅读最多'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final entry in rankedBooks.take(5))
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(bookById[entry.key]?.title ?? strings.text('已删除书籍')),
              trailing: Text(strings.duration(entry.value)),
            ),
        ],
        const SizedBox(height: 20),
        Text(
          strings.text('阅读记录'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(strings.text('这个时间范围内还没有阅读记录'))),
          ),
        for (final session in sessions)
          ListTile(
            title: Text(
              bookById[session.bookId]?.title ?? strings.text('已删除书籍'),
            ),
            subtitle: Text(
              '${_dateTime(session.startedAt)} · ${strings.duration(session.durationSeconds)}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'edit') _editSession(session);
                if (action == 'delete') _deleteSession(session);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(strings.text('修改时长'))),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(strings.text('删除记录')),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _manageCards() async {
    final strings = AppStrings.of(context);
    final draft = List<_DashboardCardId>.of(_cardOrder);
    final result = await showModalBottomSheet<List<_DashboardCardId>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final available = _DashboardCardId.values
              .where((item) => !draft.contains(item))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .72,
              child: Column(
                children: [
                  Text(
                    strings.text('管理统计卡片'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(strings.text('拖动排序，移除后可随时重新添加')),
                  ),
                  Expanded(
                    child: ReorderableListView(
                      buildDefaultDragHandles: false,
                      children: [
                        for (var index = 0; index < draft.length; index++)
                          ListTile(
                            key: ValueKey(draft[index]),
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text(strings.text(draft[index].label)),
                            trailing: IconButton(
                              tooltip: strings.text('移除'),
                              onPressed: () =>
                                  setSheetState(() => draft.removeAt(index)),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ),
                      ],
                      onReorderItem: (oldIndex, newIndex) => setSheetState(() {
                        draft.insert(newIndex, draft.removeAt(oldIndex));
                      }),
                    ),
                  ),
                  if (available.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final card in available)
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: Text(strings.text(card.label)),
                              onPressed: () =>
                                  setSheetState(() => draft.add(card)),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, draft),
                        child: Text(strings.text('保存')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (result == null) return;
    final values = await SharedPreferences.getInstance();
    await values.setStringList(
      'leeef.statistics.dashboard_cards',
      result.map((item) => item.name).toList(),
    );
    if (mounted) setState(() => _cardOrder = result);
  }

  Future<void> _editSession(ReadingSessionRecord session) async {
    final strings = AppStrings.of(context);
    final controller = TextEditingController(
      text: math.max(1, session.durationSeconds ~/ 60).toString(),
    );
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.text('修改阅读时长')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: strings.text('分钟')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.text('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text(strings.text('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || minutes < 1) return;
    await (await ref.read(
      libraryRepositoryProvider.future,
    )).updateReadingSession(
      sessionId: session.id,
      startedAt: session.startedAt,
      endedAt: session.startedAt.add(Duration(minutes: minutes)),
    );
  }

  Future<void> _deleteSession(ReadingSessionRecord session) async {
    final strings = AppStrings.of(context);
    final repository = await ref.read(libraryRepositoryProvider.future);
    await repository.deleteReadingSession(session.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.text('阅读记录已删除')),
        action: SnackBarAction(
          label: strings.text('撤销'),
          onPressed: () => repository.restoreReadingSession(session),
        ),
      ),
    );
  }

  static int _streak(List<ReadingSessionRecord> sessions) {
    final days = sessions.map((session) => _dateKey(session.startedAt)).toSet();
    var cursor = DateTime.now();
    if (!days.contains(_dateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(_dateKey(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static int _secondsSince(
    List<ReadingSessionRecord> sessions,
    DateTime cutoff,
  ) => sessions
      .where((item) => item.endedAt.isAfter(cutoff))
      .fold(0, (sum, item) => sum + item.durationSeconds);

  static String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _ReadingHeatmap extends StatelessWidget {
  const _ReadingHeatmap({required this.sessions});

  final List<ReadingSessionRecord> sessions;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final totals = <String, int>{};
    for (final session in sessions) {
      final key = _ReadingStatisticsScreenState._dateKey(session.startedAt);
      totals.update(
        key,
        (value) => value + session.durationSeconds,
        ifAbsent: () => session.durationSeconds,
      );
    }
    final today = DateTime.now();
    final first = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 83));
    final color = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var index = 0; index < 84; index++)
          Builder(
            builder: (context) {
              final day = first.add(Duration(days: index));
              final seconds =
                  totals[_ReadingStatisticsScreenState._dateKey(day)] ?? 0;
              final intensity = seconds == 0
                  ? 0.08
                  : (0.25 + math.log(seconds / 60 + 1) / 7).clamp(0.25, 1.0);
              return Tooltip(
                message:
                    '${_ReadingStatisticsScreenState._dateKey(day)} · ${strings.duration(seconds)}',
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: intensity),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ReadingTrend extends StatelessWidget {
  const _ReadingTrend({required this.sessions});
  final List<ReadingSessionRecord> sessions;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final totals = <String, int>{};
    for (final session in sessions) {
      totals.update(
        _ReadingStatisticsScreenState._dateKey(session.startedAt),
        (value) => value + session.durationSeconds,
        ifAbsent: () => session.durationSeconds,
      );
    }
    final today = DateTime.now();
    final values = [
      for (var offset = 29; offset >= 0; offset--)
        totals[_ReadingStatisticsScreenState._dateKey(
              today.subtract(Duration(days: offset)),
            )] ??
            0,
    ];
    final maximum = math.max(1, values.fold<int>(0, math.max));
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < values.length; index++)
            Expanded(
              child: Tooltip(
                message: strings.duration(values[index]),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: 6 + 110 * values[index] / maximum,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StageSummaryCard extends StatelessWidget {
  const _StageSummaryCard({
    required this.seconds,
    required this.previousSeconds,
    required this.finishedBooks,
    required this.activeBooks,
    required this.notes,
    required this.comparisonEnabled,
  });

  final int seconds;
  final int previousSeconds;
  final int finishedBooks;
  final int activeBooks;
  final int notes;
  final bool comparisonEnabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final difference = seconds - previousSeconds;
    final comparison = !comparisonEnabled
        ? strings.text('全部时间累计')
        : previousSeconds == 0
        ? (seconds == 0 ? strings.text('与上一阶段持平') : strings.text('上一阶段没有阅读记录'))
        : '${strings.text(difference >= 0 ? '增加' : '减少')} ${(difference.abs() / previousSeconds * 100).round()}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.summarize_outlined),
                const SizedBox(width: 8),
                Text(
                  strings.text('阶段汇总'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              strings.stageSummary(
                duration: strings.duration(seconds),
                comparison: comparison,
                activeBooks: activeBooks,
                finishedBooks: finishedBooks,
                notes: notes,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.progress, required this.book});
  final ReadingProgressRecord progress;
  final BookRecord? book;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: Text(
          book == null
              ? strings.text('继续阅读')
              : strings.continueBook(book!.title),
        ),
        subtitle: Text(
          '${(progress.progress * 100).toStringAsFixed(1)}%${progress.chapterTitle == null ? '' : ' · ${progress.chapterTitle}'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: book == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReaderScreen(book: book!),
                ),
              ),
      ),
    );
  }
}

class _RandomExcerptCard extends StatelessWidget {
  const _RandomExcerptCard({required this.excerpt, required this.book});
  final ExcerptRecord excerpt;
  final BookRecord? book;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.casino_outlined),
                const SizedBox(width: 8),
                Text(
                  strings.text('今日随机书摘'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText('“${excerpt.quote}”'),
            if (excerpt.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(excerpt.note!),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: book == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderScreen(book: book!),
                        ),
                      ),
                child: Text(book?.title ?? strings.text('已删除书籍')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}

enum _StatisticsRange { week, month, year, all }

enum _DashboardCardId {
  duration('阅读时长'),
  days('阅读天数'),
  streak('连续阅读'),
  books('阅读书籍'),
  notes('书摘笔记'),
  week('近 7 日'),
  month('近 30 日'),
  finished('已读完');

  const _DashboardCardId(this.label);
  final String label;
}
