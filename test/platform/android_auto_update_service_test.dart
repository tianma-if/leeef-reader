import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leeef_reader/src/platform/android_auto_update_service.dart';

class _FakeDriver implements AndroidAutoUpdateDriver {
  final statuses = StreamController<AndroidUpdateInstallStatus>.broadcast(
    sync: true,
  );
  var checks = 0;
  var starts = 0;
  var installs = 0;
  var startResult = AndroidUpdateStartResult.success;
  var checkResult = const AndroidUpdateCheckResult(
    availability: AndroidUpdateAvailability.none,
    flexibleUpdateAllowed: false,
    installStatus: AndroidUpdateInstallStatus.unknown,
  );

  @override
  Stream<AndroidUpdateInstallStatus> get installStatuses => statuses.stream;

  @override
  Future<AndroidUpdateCheckResult> checkForUpdate() async {
    checks++;
    return checkResult;
  }

  @override
  Future<AndroidUpdateStartResult> startFlexibleUpdate() async {
    starts++;
    return startResult;
  }

  @override
  Future<void> completeFlexibleUpdate() async => installs++;
}

void main() {
  test('stays inactive outside an enabled Android release build', () async {
    final driver = _FakeDriver();
    final service = AndroidAutoUpdateService(driver: driver);

    await service.initialize(enabled: false);
    await service.checkNow();

    expect(driver.checks, 0);
    expect(service.state.stage, AndroidUpdateStage.unsupported);
    service.dispose();
    await driver.statuses.close();
  });

  test('finds a flexible Google Play update', () async {
    final driver = _FakeDriver()
      ..checkResult = const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.available,
        flexibleUpdateAllowed: true,
        installStatus: AndroidUpdateInstallStatus.pending,
        availableVersionCode: 42,
      );
    final service = AndroidAutoUpdateService(driver: driver);

    await service.initialize(enabled: true);

    expect(driver.checks, 1);
    expect(service.state.stage, AndroidUpdateStage.available);
    expect(service.state.availableVersionCode, 42);
    service.dispose();
    await driver.statuses.close();
  });

  test('downloads in the background before exposing install', () async {
    final driver = _FakeDriver()
      ..checkResult = const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.available,
        flexibleUpdateAllowed: true,
        installStatus: AndroidUpdateInstallStatus.pending,
        availableVersionCode: 43,
      );
    final service = AndroidAutoUpdateService(driver: driver);
    await service.initialize(enabled: true);

    expect(
      await service.startBackgroundDownload(),
      AndroidUpdateStartResult.success,
    );
    expect(driver.starts, 1);
    expect(service.state.stage, AndroidUpdateStage.ready);

    expect(await service.installDownloadedUpdate(), isTrue);
    expect(driver.installs, 1);
    expect(service.state.stage, AndroidUpdateStage.installing);
    service.dispose();
    await driver.statuses.close();
  });

  test('recovers an update already downloaded by Google Play', () async {
    final driver = _FakeDriver()
      ..checkResult = const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.inProgress,
        flexibleUpdateAllowed: true,
        installStatus: AndroidUpdateInstallStatus.downloaded,
        availableVersionCode: 44,
      );
    final service = AndroidAutoUpdateService(driver: driver);

    await service.initialize(enabled: true);

    expect(service.state.stage, AndroidUpdateStage.ready);
    expect(service.state.availableVersionCode, 44);
    service.dispose();
    await driver.statuses.close();
  });

  test('keeps the update available when Play consent is denied', () async {
    final driver = _FakeDriver()
      ..startResult = AndroidUpdateStartResult.denied
      ..checkResult = const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.available,
        flexibleUpdateAllowed: true,
        installStatus: AndroidUpdateInstallStatus.pending,
        availableVersionCode: 45,
      );
    final service = AndroidAutoUpdateService(driver: driver);
    await service.initialize(enabled: true);

    expect(
      await service.startBackgroundDownload(),
      AndroidUpdateStartResult.denied,
    );
    expect(service.state.stage, AndroidUpdateStage.available);
    service.dispose();
    await driver.statuses.close();
  });

  test('tracks download completion reported by Play', () async {
    final driver = _FakeDriver()
      ..checkResult = const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.inProgress,
        flexibleUpdateAllowed: true,
        installStatus: AndroidUpdateInstallStatus.downloading,
        availableVersionCode: 46,
      );
    final service = AndroidAutoUpdateService(driver: driver);
    await service.initialize(enabled: true);

    expect(service.state.stage, AndroidUpdateStage.downloading);
    driver.statuses.add(AndroidUpdateInstallStatus.downloaded);
    expect(service.state.stage, AndroidUpdateStage.ready);
    expect(service.state.availableVersionCode, 46);
    service.dispose();
    await driver.statuses.close();
  });
}
