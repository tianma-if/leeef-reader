import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/reader/reader_chrome_footer.dart';
import 'package:leeef_reader/src/features/reader/reader_page_turn_policy.dart';
import 'package:leeef_reader/src/features/reader/reader_sidebar.dart';

/// Desktop copies Readest: a pinned left sidebar plus in-page chapter/page
/// chrome. Hovering the reading pane still reveals the header and footer.
/// Mobile keeps overlay header/footer; the same sidebar opens as a sheet.
class ReaderChromeScaffold extends StatelessWidget {
  const ReaderChromeScaffold({
    required this.body,
    required this.header,
    required this.footer,
    super.key,
    this.sidebar,
    this.sidebarVisible = false,
    this.sidebarPinned = false,
    this.chromeVisible = false,
    this.chapterTitle,
    this.pageLabel,
    this.showChapterTitle = true,
    this.showPageLabel = true,
    this.onDismissSidebar,
    this.paperColor,
  });

  final Widget body;
  final PreferredSizeWidget header;
  final Widget footer;
  final Widget? sidebar;
  final bool sidebarVisible;
  final bool sidebarPinned;
  final bool chromeVisible;
  final String? chapterTitle;
  final String? pageLabel;
  final bool showChapterTitle;
  final bool showPageLabel;
  final VoidCallback? onDismissSidebar;
  final Color? paperColor;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopReaderPlatform();
    final hasSidebar = sidebar != null && sidebarVisible;
    final pinned = desktop && hasSidebar && sidebarPinned;
    final overlaySidebar = hasSidebar && !pinned;
    final hidePageChrome = chromeVisible;
    final reading = Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (!hidePageChrome &&
            showChapterTitle &&
            chapterTitle != null &&
            chapterTitle!.trim().isNotEmpty)
          _ChapterTitle(chapterTitle!.trim()),
        if (!hidePageChrome &&
            showPageLabel &&
            pageLabel != null &&
            pageLabel!.trim().isNotEmpty)
          _PageLabel(pageLabel!.trim()),
        if (chromeVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ReaderChromeOverlayBar(child: header),
          ),
        if (chromeVisible)
          Positioned(left: 0, right: 0, bottom: 0, child: footer),
        if (overlaySidebar) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismissSidebar,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: desktop ? 0.2 : 0.5),
              ),
            ),
          ),
          if (desktop)
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: readerSidebarWidth,
              child: sidebar!,
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: MediaQuery.paddingOf(context).top + 8,
              child: sidebar!,
            ),
        ],
      ],
    );
    return Scaffold(
      backgroundColor: paperColor,
      body: pinned
          ? Row(
              children: [
                SizedBox(
                  key: const Key('reader-sidebar'),
                  width: readerSidebarWidth,
                  child: sidebar,
                ),
                Expanded(child: reading),
              ],
            )
          : KeyedSubtree(
              key: overlaySidebar && !desktop
                  ? const Key('reader-sidebar')
                  : null,
              child: reading,
            ),
    );
  }
}

class _ChapterTitle extends StatelessWidget {
  const _ChapterTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(28, top + 8, 28, 0),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageLabel extends StatelessWidget {
  const _PageLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      right: 28,
      bottom: bottom + 12,
      child: IgnorePointer(
        child: Text(
          key: const Key('reader-page-info'),
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            fontWeight: FontWeight.w300,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
