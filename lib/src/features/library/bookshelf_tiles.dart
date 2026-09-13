import 'package:flutter/material.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/features/library/bookshelf_cover.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';

class BookshelfBookTile extends StatelessWidget {
  const BookshelfBookTile({
    super.key,
    required this.book,
    required this.coverFit,
    this.progress,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final BookRecord book;
  final BoxFit coverFit;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final clamped = progress?.clamp(0.0, 1.0);
    final finished = clamped != null && clamped >= 0.999;
    final progressLabel = clamped == null
        ? null
        : finished
        ? strings.text('已读完')
        : '${(clamped * 100).round()}%';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onSecondaryTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookshelfCoverFrame(
                child: BookshelfCover(
                  title: book.title,
                  author: book.author,
                  coverPath: book.coverPath,
                  fit: coverFit,
                  heroTag: 'book-cover-${book.id}',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (progressLabel != null)
                      Expanded(
                        child: Text(
                          progressLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.55),
                                fontSize: 11,
                              ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (!book.isAvailableLocally)
                      Icon(
                        Icons.cloud_download_outlined,
                        size: 14,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookshelfFolderTile extends StatelessWidget {
  const BookshelfFolderTile({
    super.key,
    required this.name,
    required this.covers,
    required this.coverFit,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final String name;
  final List<BookRecord> covers;
  final BoxFit coverFit;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onSecondaryTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookshelfCoverFrame(
                child: ColoredBox(
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _mosaicCell(0)),
                              const SizedBox(width: 4),
                              Expanded(child: _mosaicCell(1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(child: _mosaicCell(2)),
                              const SizedBox(width: 4),
                              Expanded(child: _mosaicCell(3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mosaicCell(int index) {
    if (index >= covers.length) return const SizedBox.expand();
    final book = covers[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: BookshelfCover(
        title: book.title,
        author: book.author,
        coverPath: book.coverPath,
        fit: coverFit,
        isPreview: true,
      ),
    );
  }
}

class BookshelfImportTile extends StatelessWidget {
  const BookshelfImportTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookshelfCoverFrame(
                elevated: false,
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Icon(
                    Icons.add,
                    size: 40,
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.importBook,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.2,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
