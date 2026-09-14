import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/page_slide/smooth_page_slide.dart';

void main() {
  Widget frame({
    required int page,
    required ValueChanged<int> onPageChanged,
    Key? rightZoneKey,
  }) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 320,
        height: 480,
        child: SmoothPageSlide(
          pageIndex: page,
          pageCount: 3,
          onPageChanged: onPageChanged,
          rightZoneKey: rightZoneKey,
          pageBuilder: (context, index) => ColoredBox(
            color: index == 0 ? Colors.white : Colors.black,
            child: Text('page-$index'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a halfway drag plus settle advances to the next page', (
    tester,
  ) async {
    var page = 0;
    await tester.pumpWidget(frame(page: page, onPageChanged: (index) => page = index));

    final rect = tester.getRect(find.byType(SmoothPageSlide));
    await tester.timedDragFrom(
      Offset(rect.right - 24, rect.center.dy),
      Offset(-rect.width * 0.7, 0),
      const Duration(milliseconds: 280),
    );
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(find.text('page-1'), findsOneWidget);
  });

  testWidgets('a short drag snaps back to the current page', (tester) async {
    var page = 0;
    await tester.pumpWidget(frame(page: page, onPageChanged: (index) => page = index));

    final rect = tester.getRect(find.byType(SmoothPageSlide));
    await tester.timedDragFrom(
      rect.center,
      const Offset(-16, 0),
      const Duration(milliseconds: 120),
    );
    await tester.pumpAndSettle();
    expect(page, 0);
    expect(find.text('page-0'), findsOneWidget);
  });

  testWidgets('right-edge tap turns the page', (tester) async {
    var page = 0;
    await tester.pumpWidget(
      frame(
        page: page,
        onPageChanged: (index) => page = index,
        rightZoneKey: const Key('txt-slide-right-zone'),
      ),
    );

    final rect = tester.getRect(find.byType(SmoothPageSlide));
    await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
    await tester.pumpAndSettle();
    expect(page, 1);
  });
}
