import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/notes/excerpt_share_card_screen.dart';

void main() {
  testWidgets('share-card color swatches expose names and selection state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        supportedLocales: [Locale('en')],
        home: ExcerptShareCardScreen(quote: 'Accessible reading', book: null),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text color'));
    await tester.pumpAndSettle();

    final selected = tester
        .getSemantics(find.bySemanticsLabel('Color #22452D'))
        .getSemanticsData();
    expect(selected.attributedLabel.string, 'Color #22452D');
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    expect(selected.hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel('Color #000000'), findsOneWidget);
    expect(find.bySemanticsLabel('Color #FFFFFF'), findsOneWidget);

    semantics.dispose();
  });
}
