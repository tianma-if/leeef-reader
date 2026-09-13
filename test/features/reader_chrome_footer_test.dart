import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/features/reader/reader_chrome_footer.dart';
import 'package:leeef_reader/src/reader/reader_preferences.dart';

void main() {
  testWidgets('mobile footer shows four actions instead of a live progress pill', (
    tester,
  ) async {
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
  });
}
