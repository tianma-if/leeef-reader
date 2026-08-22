import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app.dart';

void main() {
  testWidgets('library empty state is visible', (tester) async {
    await tester.pumpWidget(const LeeefApp());

    expect(find.text('书库'), findsNWidgets(2));
    expect(find.text('开始你的书库'), findsOneWidget);
    expect(find.text('导入书籍'), findsOneWidget);
  });
}
