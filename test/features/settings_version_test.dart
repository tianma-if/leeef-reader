import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/app_providers.dart';
import 'package:leeef_reader/src/platform/app_log.dart';
import 'package:leeef_reader/src/platform/app_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PackageInfo.setMockInitialValues(
      appName: 'Leeef Reader',
      packageName: 'if.tianma.leeefreader',
      version: '1.6.0',
      buildNumber: '23',
      buildSignature: '',
    );
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
    await tester.scrollUntilVisible(
      find.text('当前版本 1.6.0（23）'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }

  tearDown(() => AppUpdateService.debugCheck = null);

  test('startup log version uses package version and build number', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Leeef Reader',
      packageName: 'if.tianma.leeefreader',
      version: '1.6.0',
      buildNumber: '23',
      buildSignature: '',
    );
    expect(await AppLog.installedVersionLabel(), '1.6.0+23');
  });

  testWidgets('settings page shows the installed app version', (tester) async {
    AppUpdateService.debugCheck = () async => AppUpdateInfo(
      currentVersion: '1.6.0',
      latestVersion: '1.6.0',
      releaseNotes: '',
      releaseUrl: Uri.parse(
        'https://github.com/tianma-if/leeef-reader/releases',
      ),
    );
    await openSettings(tester);
    expect(find.text('当前版本 1.6.0（23）'), findsOneWidget);
    expect(find.text('已是最新版本'), findsOneWidget);
    expect(find.text('检查'), findsOneWidget);
  });

  testWidgets('settings page shows when a newer release exists', (
    tester,
  ) async {
    AppUpdateService.debugCheck = () async => AppUpdateInfo(
      currentVersion: '1.6.0',
      latestVersion: '1.7.0',
      releaseNotes: '',
      releaseUrl: Uri.parse(
        'https://github.com/tianma-if/leeef-reader/releases',
      ),
    );
    await openSettings(tester);
    expect(find.text('当前版本 1.6.0（23）'), findsOneWidget);
    expect(find.text('发现新版本 1.7.0'), findsOneWidget);
  });
}
