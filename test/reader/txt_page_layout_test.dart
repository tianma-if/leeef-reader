import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/txt_layout_paginator.dart';
import 'package:leeef_reader/src/features/reader/txt_page_layout.dart';

void main() {
  for (final viewport in [
    const Size(390, 720),
    const Size(1200, 800),
    const Size(1920, 874),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('actual selectable text fits and fills $viewport at $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = viewport;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const layout = TxtPageLayout();
        const style = TextStyle(
          inherit: false,
          textBaseline: TextBaseline.alphabetic,
          fontSize: 18,
          height: 1.65,
          color: Colors.black,
        );
        final scaler = TextScaler.linear(scale);
        final available = layout.contentSize(viewport);
        final pages = paginateTxtForLayout(
          text: '测试正文 Wide WWW 窄iii 👩🏽‍💻，分页连续。' * 400,
          maxWidth: available.width,
          maxHeight: available.height,
          style: style,
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          buildDisplayText: (s) => TxtDisplayText(
            text: s,
            offsets: List.generate(s.length + 1, (i) => i),
          ),
        );
        for (final page in [pages.first, pages.last]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TxtPageBody(
                  layout: layout,
                  child: SelectableText(
                    page.text,
                    style: style,
                    textScaler: scaler,
                  ),
                ),
              ),
            ),
          );
          final rect = tester.getRect(find.byType(SelectableText));
          expect(rect.top, 24);
          expect(rect.left, 24);
          expect(rect.width, viewport.width - 48);
          final editable = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          final lastCaret = editable.getLocalRectForCaret(
            TextPosition(offset: page.text.length),
          );
          expect(lastCaret.bottom, lessThanOrEqualTo(available.height + 1));
          expect((editable.offset as ScrollPosition).maxScrollExtent, 0);
          if (page == pages.first) {
            expect(
              rect.height,
              greaterThan(available.height - 18 * 1.65 * scale - 1),
            );
          }
        }
      });
    }
  }

  test('safe-area reserve is shared with pagination', () {
    const layout = TxtPageLayout(margin: 32, bottomInset: 34);
    expect(layout.padding, const EdgeInsets.fromLTRB(32, 24, 32, 106));
    expect(layout.contentSize(const Size(400, 800)), const Size(333, 670));
  });
}
