import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';

void main() {
  testWidgets('library empty state is visible', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryBooksProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const LeeefApp(),
      ),
    );
    await tester.pump();

    expect(find.text('书库'), findsNWidgets(2));
    expect(find.text('开始你的书库'), findsOneWidget);
    expect(find.text('导入书籍'), findsOneWidget);
  });
}
