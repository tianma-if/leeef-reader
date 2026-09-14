import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/reader_chrome_footer.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';

void main() {
  testWidgets(
    'mobile footer shows four actions instead of a live progress pill',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReaderChromeFooter(
                progress: 0.42,
                progressLabel: '42%',
                preferences: const ReaderPreferences(),
                onPreferencesChanged: (_) {},
                onToc: () {},
              ),
            ),
          ),
        );

        expect(find.text('42%'), findsNothing);
        expect(find.byIcon(Icons.list), findsOneWidget);
        expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
        expect(find.byIcon(Icons.tune), findsOneWidget);
        expect(find.byIcon(Icons.text_fields), findsOneWidget);

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();
        expect(find.text('42%'), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('night paper theme is applied on the same tap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    ReaderPreferences? updated;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderChromeFooter(
              progress: 0.42,
              progressLabel: '42%',
              preferences: const ReaderPreferences(),
              onPreferencesChanged: (value) => updated = value,
              onToc: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.wb_sunny_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip).at(1));
      await tester.pump();

      expect(updated?.foreground, '#d8d8d8');
      expect(updated?.background, '#151515');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop footer is a progress bar instead of a floating pill', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderChromeFooter(
              progress: 0.42,
              progressLabel: '15 / 226',
              preferences: const ReaderPreferences(),
              onPreferencesChanged: (_) {},
              onPrevious: () {},
              onNext: () {},
              onSeekProgress: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('15 / 226'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.list), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
