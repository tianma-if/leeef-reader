import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/features/settings/pairing_qr_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop settings offer a pairing QR generator', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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
        find.text('生成配对二维码'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('生成配对二维码'), findsOneWidget);
      expect(find.text('扫描配对二维码'), findsNothing);
      expect(find.text('手机扫描后即可同步这台电脑上的存储、AI 和阅读配置'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS settings offer a pairing QR scanner', (tester) async {
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
        find.text('扫描配对二维码'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('扫描配对二维码'), findsOneWidget);
      expect(find.text('扫描电脑上的二维码，同步已配置的存储、AI 和阅读设置'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('host pairing panel renders a QR code for the invite', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(
          body: SingleChildScrollView(
            child: PairingQrPanel(
              code: 'ABCD-EFGH-IJKL',
              payload: 'leeef://pair?v=1&c=ABCD-EFGH-IJKL',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABCD-EFGH-IJKL'), findsOneWidget);
    expect(find.text('用手机扫描这个二维码。两台设备需要连接同一个局域网。'), findsOneWidget);
  });
}
