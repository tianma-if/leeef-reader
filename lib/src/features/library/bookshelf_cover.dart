import 'dart:io';

import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/library/bookshelf_layout.dart';

class BookshelfCover extends StatelessWidget {
  const BookshelfCover({
    super.key,
    required this.title,
    this.author,
    this.coverPath,
    this.fit = BoxFit.cover,
    this.showSpine = true,
    this.heroTag,
    this.isPreview = false,
  });

  final String title;
  final String? author;
  final String? coverPath;
  final BoxFit fit;
  final bool showSpine;
  final String? heroTag;
  final bool isPreview;

  bool get _hasCover {
    final path = coverPath;
    return path != null && path.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final cover = _hasCover
        ? Image.file(
            File(coverPath!),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            alignment: fit == BoxFit.contain
                ? Alignment.bottomCenter
                : Alignment.center,
            errorBuilder: (_, _, _) => _FallbackCover(
              title: title,
              author: author,
              isPreview: isPreview,
            ),
          )
        : _FallbackCover(title: title, author: author, isPreview: isPreview);
    final framed = Stack(
      fit: StackFit.expand,
      children: [cover, if (showSpine && _hasCover) const _BookSpineOverlay()],
    );
    if (heroTag == null) return framed;
    return Hero(tag: heroTag!, child: framed);
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({
    required this.title,
    this.author,
    required this.isPreview,
  });

  final String title;
  final String? author;
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontFamily: 'serif',
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      height: 1.2,
      fontSize: isPreview ? 8 : 14,
    );
    final authorStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'serif',
      color: scheme.onSurface.withValues(alpha: 0.5),
      fontSize: isPreview ? 7 : 12,
    );
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.all(isPreview ? 4 : 8),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  title,
                  maxLines: isPreview ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: titleStyle,
                ),
              ),
            ),
            const Spacer(),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  author ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: authorStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Left-edge shading that reads as a bound book spine, plus a thin page stack
/// on the right — the same skeuomorphic overlay Readest uses on cropped covers.
class _BookSpineOverlay extends StatelessWidget {
  const _BookSpineOverlay();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0x73000000),
              Color(0x3D000000),
              Color(0x66FFFFFF),
              Color(0x14000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0x33FFFFFF),
              Color(0x59F5F0E6),
            ],
            stops: [0.0, 0.012, 0.028, 0.045, 0.08, 0.94, 0.975, 1.0],
          ),
        ),
      ),
    );
  }
}

class BookshelfCoverFrame extends StatelessWidget {
  const BookshelfCoverFrame({
    super.key,
    required this.child,
    this.elevated = true,
  });

  final Widget child;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kBookshelfCoverAspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          boxShadow: elevated
              ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(2), child: child),
      ),
    );
  }
}
