import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openMobileSettings(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = platform;
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
          bookshelfEntriesProvider.overrideWith(
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
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform settings hide service credentials and promote QR pairing',
      (tester) async {
        try {
          await openMobileSettings(tester, platform);

          await tester.scrollUntilVisible(
            find.text('扫描配对二维码'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('扫描配对二维码'), findsOneWidget);
          expect(find.text('请先在电脑上配置对象存储和 AI，再扫描二维码同步到此设备'), findsOneWidget);

          await tester.scrollUntilVisible(
            find.text('AI 上下文翻译'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('在电脑上配置后会自动同步到此设备'), findsOneWidget);
          expect(find.text('AI Provider、Prompt 与 Tools'), findsNothing);
          expect(find.text('AI Prompt 管理'), findsNothing);
          expect(find.text('检测 AI 模型'), findsNothing);
          expect(find.text('TTS 朗读服务'), findsNothing);
          expect(find.text('OpenAI-compatible API 地址'), findsNothing);
          expect(find.text('API Key'), findsNothing);
          expect(find.text('配置 AI 翻译'), findsNothing);
          expect(find.text('HTTP/HTTPS 代理'), findsNothing);
          expect(find.text('完整备份'), findsNothing);
          expect(find.text('自定义书籍数据目录'), findsNothing);
          expect(find.text('EPUB JavaScript'), findsNothing);

          await tester.scrollUntilVisible(
            find.text('立即同步'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('扫码同步'), findsOneWidget);
          expect(find.text('同步方式'), findsNothing);
          expect(find.text('检测对象存储'), findsNothing);
          expect(find.text('配置对象存储'), findsNothing);
          expect(find.text('WebDAV 服务器'), findsNothing);
          expect(find.text('生成配对二维码'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
