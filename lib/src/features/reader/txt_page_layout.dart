import 'package:flutter/material.dart';

/// Shared geometry for pagination, visible pages, and page-turn snapshots.
class TxtPageLayout {
  const TxtPageLayout({this.margin = 24, this.topInset = 0});

  // RenderEditable reserves its 2px cursor plus a 1px caret gap, even for
  // read-only SelectableText. Measure the same usable line width.
  static const caretMargin = 3.0;

  final double margin;
  final double topInset;

  // Overlay chrome and the home indicator sit on top of the page. Keep the
  // user margin on every side, plus the status-bar inset at the top so text
  // does not run under the clock/notch.
  EdgeInsets get padding =>
      EdgeInsets.fromLTRB(margin, margin + topInset, margin, margin);

  Size contentSize(Size viewport) => Size(
    (viewport.width - padding.horizontal - caretMargin).clamp(
      1.0,
      double.infinity,
    ),
    (viewport.height - padding.vertical).clamp(1.0, double.infinity),
  );
}

class TxtPageBody extends StatelessWidget {
  const TxtPageBody({required this.layout, required this.child, super.key});

  final TxtPageLayout layout;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Padding(
      padding: layout.padding,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}
