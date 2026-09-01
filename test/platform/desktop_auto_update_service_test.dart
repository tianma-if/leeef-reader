import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/desktop_auto_update_service.dart';

class _FakeDriver implements DesktopAutoUpdateDriver {
  UpdaterListener? listener;
  String? feedUrl;
  int? interval;
  var checks = 0;
  var installs = 0;
  var installResult = true;
  final operations = <String>[];

  @override
  void addListener(UpdaterListener value) => listener = value;

  @override
  void removeListener(UpdaterListener value) {
    if (identical(listener, value)) listener = null;
  }

  @override
  Future<void> setFeedURL(String value) async {
    operations.add('feed');
    feedUrl = value;
  }

  @override
  Future<void> setScheduledCheckInterval(int seconds) async {
    operations.add('interval');
    interval = seconds;
  }

  @override
  Future<void> checkInBackground() async {
    operations.add('check');
    checks++;
  }

  @override
  Future<bool> installDownloadedUpdate() async {
    installs++;
    return installResult;
  }
}

void main() {
  test('stays inactive outside an enabled release build', () async {
    final driver = _FakeDriver();
    final service = DesktopAutoUpdateService(driver: driver);

    await service.initialize(enabled: false);
    await service.checkNow();

    expect(driver.listener, isNull);
    expect(driver.checks, 0);
    expect(service.state.stage, DesktopUpdateStage.unsupported);
    service.dispose();
  });

  test('initializes a silent scheduled update check', () async {
    final driver = _FakeDriver();
    final service = DesktopAutoUpdateService(driver: driver);

    await service.initialize(enabled: true);

    expect(driver.feedUrl, DesktopAutoUpdateService.feedUrl);
    expect(driver.interval, DesktopAutoUpdateService.checkInterval.inSeconds);
    expect(driver.checks, 1);
    expect(driver.operations, ['interval', 'feed', 'check']);
    expect(service.state.stage, DesktopUpdateStage.checking);
    service.dispose();
  });

  test(
    'only exposes install after Sparkle reports a downloaded update',
    () async {
      final driver = _FakeDriver();
      final service = DesktopAutoUpdateService(driver: driver);
      await service.initialize(enabled: true);

      service.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.2.0'),
      );
      expect(service.state.stage, DesktopUpdateStage.downloading);
      expect(await service.installDownloadedUpdate(), isFalse);
      expect(driver.installs, 0);

      service.onUpdaterBeforeQuitForUpdate(
        const AppcastItem(displayVersionString: '1.2.0'),
      );
      expect(service.state.stage, DesktopUpdateStage.ready);
      expect(service.state.version, '1.2.0');
      expect(await service.installDownloadedUpdate(), isTrue);
      expect(driver.installs, 1);
      service.dispose();
    },
  );

  test('also accepts the legacy update-downloaded readiness event', () async {
    final driver = _FakeDriver();
    final service = DesktopAutoUpdateService(driver: driver);
    await service.initialize(enabled: true);

    service.onUpdaterUpdateDownloaded(
      const AppcastItem(displayVersionString: '1.3.0'),
    );

    expect(service.state.stage, DesktopUpdateStage.ready);
    expect(service.state.version, '1.3.0');
    service.dispose();
  });

  test('keeps update-check failures non-blocking', () async {
    final driver = _FakeDriver();
    final service = DesktopAutoUpdateService(driver: driver);
    await service.initialize(enabled: true);

    service.onUpdaterError(UpdaterError('offline'));

    expect(service.state.stage, DesktopUpdateStage.failed);
    expect(service.state.error, isA<UpdaterError>());
    service.dispose();
  });
}
