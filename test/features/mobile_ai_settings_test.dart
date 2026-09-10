import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('iOS settings hide AI API key and provider configuration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
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

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('AI 上下文翻译'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('在电脑上配置后会自动同步到此设备'), findsOneWidget);
      expect(find.text('AI Provider、Prompt 与 Tools'), findsNothing);
      expect(find.text('检测 AI 模型'), findsNothing);
      expect(find.text('TTS 朗读服务'), findsNothing);
      expect(find.text('OpenAI-compatible API 地址'), findsNothing);
      expect(find.text('API Key'), findsNothing);
      expect(find.text('配置 AI 翻译'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
