import 'package:flutter/material.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';

/// Readest-style mobile header: back, bookmark, notes, overflow. No title —
/// the chapter name stays in the page margin.
class ReaderChromeHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const ReaderChromeHeader({
    required this.heroTag,
    super.key,
    this.onBookmark,
    this.onNotes,
    this.onSearch,
    this.onReadingSettings,
    this.onTts,
    this.onAi,
    this.onCopyChapter,
    this.onToc,
  });

  final String heroTag;
  final VoidCallback? onBookmark;
  final VoidCallback? onNotes;
  final VoidCallback? onSearch;
  final VoidCallback? onReadingSettings;
  final VoidCallback? onTts;
  final ValueChanged<String>? onAi;
  final VoidCallback? onCopyChapter;
  final VoidCallback? onToc;

  static const double barHeight = 44;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      height: barHeight,
      child: Row(
        children: [
          Hero(
            tag: heroTag,
            child: const Material(
              color: Colors.transparent,
              child: BackButton(),
            ),
          ),
          IconButton(
            tooltip: strings.text('添加书签'),
            onPressed: onBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          const Spacer(),
          IconButton(
            tooltip: strings.text('批注'),
            onPressed: onNotes,
            icon: const Icon(Icons.edit_note_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: strings.text('更多阅读操作'),
            icon: const Icon(Icons.menu),
            onSelected: (value) => switch (value) {
              'search' => onSearch?.call(),
              'style' => onReadingSettings?.call(),
              'tts' => onTts?.call(),
              'toc' => onToc?.call(),
              'copy-chapter' => onCopyChapter?.call(),
              'chat' || 'full-summary' || 'translate' => onAi?.call(value),
              _ => null,
            },
            itemBuilder: (_) => [
              if (onSearch != null)
                PopupMenuItem(
                  value: 'search',
                  child: Text(strings.text('书内搜索')),
                ),
              if (onReadingSettings != null)
                PopupMenuItem(
                  value: 'style',
                  child: Text(strings.text('阅读样式')),
                ),
              if (onTts != null)
                PopupMenuItem(value: 'tts', child: Text(strings.text('朗读'))),
              if (onAi != null) ...[
                PopupMenuItem(
                  value: 'chat',
                  child: Text(strings.text('基于当前章节对话')),
                ),
                PopupMenuItem(
                  value: 'translate',
                  child: Text(strings.text('全文翻译')),
                ),
              ],
              if (onToc != null)
                PopupMenuItem(value: 'toc', child: Text(strings.text('目录'))),
              if (onCopyChapter != null)
                PopupMenuItem(
                  value: 'copy-chapter',
                  child: Text(strings.text('复制当前章节正文')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
