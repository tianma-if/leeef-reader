import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/page_slide_switcher.dart';

void main() {
  testWidgets('adjacent pages share one continuous seam while sliding', (
    tester,
  ) async {
    Widget frame({required int page, required int direction}) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 480,
          child: PageSlideSwitcher(
            direction: direction,
            duration: const Duration(milliseconds: 240),
            child: ColoredBox(
              key: ValueKey('page-$page'),
              color: page == 1 ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(frame(page: 1, direction: 1));
    await tester.pumpWidget(frame(page: 2, direction: 1));
    await tester.pump(const Duration(milliseconds: 120));

    final outgoing = tester.getRect(find.byKey(const ValueKey('page-1')));
    final incoming = tester.getRect(find.byKey(const ValueKey('page-2')));
    expect(outgoing.left, lessThan(240));
    expect(incoming.left, greaterThan(240));
    expect(outgoing.right, closeTo(incoming.left, 0.01));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-1')), findsNothing);
    expect(find.byKey(const ValueKey('page-2')), findsOneWidget);
  });
}
