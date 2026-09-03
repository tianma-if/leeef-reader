import 'package:flutter/material.dart';

/// Shared geometry for pagination, visible pages, and page-turn snapshots.
class TxtPageLayout {
  const TxtPageLayout({this.margin = 24, this.bottomInset = 0});

  // RenderEditable reserves its 2px cursor plus a 1px caret gap, even for
  // read-only SelectableText. Measure the same usable line width.
  static const caretMargin = 3.0;

  final double margin;
  final double bottomInset;

  // 48px footer controls, 12px outer spacing, and 12px separation from text.
  // Keep this reserve when controls hide so hovering does not repaginate.
  EdgeInsets get padding =>
      EdgeInsets.fromLTRB(margin, 24, margin, 72 + bottomInset);

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
