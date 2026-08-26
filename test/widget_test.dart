import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('library empty state is visible', (tester) async {
    SharedPreferences.setMockInitialValues({
      'leeef.appearance.locale': 'zh',
      'leeef.onboarding.completed': true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value(const [])),
          bookshelvesProvider.overrideWith((ref) => Stream.value(const [])),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          readingProgressesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('书库'), findsNWidgets(2));
    expect(find.text('开始你的书库'), findsOneWidget);
    expect(find.text('导入书籍'), findsOneWidget);
  });

  testWidgets('English locale localizes the primary library experience', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'leeef.appearance.locale': 'en',
      'leeef.onboarding.completed': true,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value(const [])),
          bookshelvesProvider.overrideWith((ref) => Stream.value(const [])),
          tagsProvider.overrideWith((ref) => Stream.value(const [])),
          readingProgressesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Library'), findsNWidgets(2));
    expect(find.text('Start your library'), findsOneWidget);
    expect(find.text('Import books'), findsOneWidget);
  });
}
