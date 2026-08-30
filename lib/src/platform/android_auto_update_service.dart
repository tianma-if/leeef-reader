import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart' as play;
import 'package:leeef_reader/src/platform/app_log.dart';

enum AndroidUpdateStage {
  unsupported,
  idle,
  checking,
  available,
  downloading,
  ready,
  installing,
  failed,
}

enum AndroidUpdateAvailability { none, available, inProgress }

enum AndroidUpdateInstallStatus {
  unknown,
  pending,
  downloading,
  downloaded,
  installing,
  installed,
  failed,
  canceled,
}

enum AndroidUpdateStartResult { success, denied, failed }

@immutable
class AndroidUpdateCheckResult {
  const AndroidUpdateCheckResult({
    required this.availability,
    required this.flexibleUpdateAllowed,
    required this.installStatus,
    this.availableVersionCode,
  });

  final AndroidUpdateAvailability availability;
  final bool flexibleUpdateAllowed;
  final AndroidUpdateInstallStatus installStatus;
  final int? availableVersionCode;
}

@immutable
class AndroidUpdateState {
  const AndroidUpdateState({
    required this.stage,
    this.availableVersionCode,
    this.error,
  });

  const AndroidUpdateState.unsupported()
    : this(stage: AndroidUpdateStage.unsupported);

  final AndroidUpdateStage stage;
  final int? availableVersionCode;
  final Object? error;

  bool get hasActionableUpdate =>
      stage == AndroidUpdateStage.available ||
      stage == AndroidUpdateStage.downloading ||
      stage == AndroidUpdateStage.ready;

  bool get isReady => stage == AndroidUpdateStage.ready;
}

abstract interface class AndroidAutoUpdateDriver {
  Stream<AndroidUpdateInstallStatus> get installStatuses;
  Future<AndroidUpdateCheckResult> checkForUpdate();
  Future<AndroidUpdateStartResult> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
}

class GooglePlayAutoUpdateDriver implements AndroidAutoUpdateDriver {
  @override
  Stream<AndroidUpdateInstallStatus> get installStatuses =>
      play.InAppUpdate.installUpdateListener.map(_mapInstallStatus);

  @override
  Future<AndroidUpdateCheckResult> checkForUpdate() async {
    final result = await play.InAppUpdate.checkForUpdate();
    return AndroidUpdateCheckResult(
      availability: switch (result.updateAvailability) {
        play.UpdateAvailability.updateAvailable =>
          AndroidUpdateAvailability.available,
        play.UpdateAvailability.developerTriggeredUpdateInProgress =>
          AndroidUpdateAvailability.inProgress,
        _ => AndroidUpdateAvailability.none,
      },
      flexibleUpdateAllowed: result.flexibleUpdateAllowed,
      installStatus: _mapInstallStatus(result.installStatus),
      availableVersionCode: result.availableVersionCode,
    );
  }

  @override
  Future<AndroidUpdateStartResult> startFlexibleUpdate() async {
    final result = await play.InAppUpdate.startFlexibleUpdate();
    return switch (result) {
      play.AppUpdateResult.success => AndroidUpdateStartResult.success,
      play.AppUpdateResult.userDeniedUpdate => AndroidUpdateStartResult.denied,
      play.AppUpdateResult.inAppUpdateFailed => AndroidUpdateStartResult.failed,
    };
  }

  @override
  Future<void> completeFlexibleUpdate() =>
      play.InAppUpdate.completeFlexibleUpdate();

  static AndroidUpdateInstallStatus _mapInstallStatus(
    play.InstallStatus status,
  ) => switch (status) {
    play.InstallStatus.pending => AndroidUpdateInstallStatus.pending,
    play.InstallStatus.downloading => AndroidUpdateInstallStatus.downloading,
    play.InstallStatus.downloaded => AndroidUpdateInstallStatus.downloaded,
    play.InstallStatus.installing => AndroidUpdateInstallStatus.installing,
    play.InstallStatus.installed => AndroidUpdateInstallStatus.installed,
    play.InstallStatus.failed => AndroidUpdateInstallStatus.failed,
    play.InstallStatus.canceled => AndroidUpdateInstallStatus.canceled,
    play.InstallStatus.unknown => AndroidUpdateInstallStatus.unknown,
  };
}

class AndroidAutoUpdateService extends ChangeNotifier {
  AndroidAutoUpdateService({AndroidAutoUpdateDriver? driver})
    : _driver = driver ?? GooglePlayAutoUpdateDriver();

  static final instance = AndroidAutoUpdateService();
  static const checkInterval = Duration(hours: 6);

  final AndroidAutoUpdateDriver _driver;
  StreamSubscription<AndroidUpdateInstallStatus>? _statusSubscription;
  var _initialized = false;
  var _enabled = false;
  var _state = const AndroidUpdateState.unsupported();

  AndroidUpdateState get state => _state;

  Future<void> initialize({bool? enabled}) async {
    if (_initialized) return;
    _initialized = true;
    _enabled = enabled ?? (Platform.isAndroid && kReleaseMode);
    if (!_enabled) return;

    _statusSubscription = _driver.installStatuses.listen(
      _handleInstallStatus,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(AppLog.error(error, stackTrace));
      },
    );
    await checkNow();
  }

  Future<void> checkNow() async {
    if (!_enabled ||
        _state.stage == AndroidUpdateStage.checking ||
        _state.stage == AndroidUpdateStage.downloading ||
        _state.stage == AndroidUpdateStage.ready ||
        _state.stage == AndroidUpdateStage.installing) {
      return;
    }
    _setState(
      AndroidUpdateState(
        stage: AndroidUpdateStage.checking,
        availableVersionCode: _state.availableVersionCode,
      ),
    );
    try {
      final result = await _driver.checkForUpdate();
      final versionCode = result.availableVersionCode;
      if (result.installStatus == AndroidUpdateInstallStatus.downloaded) {
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.ready,
            availableVersionCode: versionCode,
          ),
        );
      } else if (result.availability == AndroidUpdateAvailability.available &&
          result.flexibleUpdateAllowed) {
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.available,
            availableVersionCode: versionCode,
          ),
        );
      } else if (result.availability == AndroidUpdateAvailability.inProgress) {
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.downloading,
            availableVersionCode: versionCode,
          ),
        );
      } else {
        _setState(const AndroidUpdateState(stage: AndroidUpdateStage.idle));
      }
    } on Object catch (error, stackTrace) {
      _setState(
        AndroidUpdateState(stage: AndroidUpdateStage.failed, error: error),
      );
      await AppLog.error(error, stackTrace);
    }
  }

  Future<AndroidUpdateStartResult> startBackgroundDownload() async {
    if (_state.stage != AndroidUpdateStage.available) {
      return AndroidUpdateStartResult.failed;
    }
    _setState(
      AndroidUpdateState(
        stage: AndroidUpdateStage.downloading,
        availableVersionCode: _state.availableVersionCode,
      ),
    );
    try {
      final result = await _driver.startFlexibleUpdate();
      if (result == AndroidUpdateStartResult.success) {
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.ready,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      } else {
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.available,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      }
      return result;
    } on Object catch (error, stackTrace) {
      _setState(
        AndroidUpdateState(
          stage: AndroidUpdateStage.available,
          availableVersionCode: _state.availableVersionCode,
          error: error,
        ),
      );
      await AppLog.error(error, stackTrace);
      return AndroidUpdateStartResult.failed;
    }
  }

  Future<bool> installDownloadedUpdate() async {
    if (!_state.isReady) return false;
    _setState(
      AndroidUpdateState(
        stage: AndroidUpdateStage.installing,
        availableVersionCode: _state.availableVersionCode,
      ),
    );
    try {
      await _driver.completeFlexibleUpdate();
      return true;
    } on Object catch (error, stackTrace) {
      _setState(
        AndroidUpdateState(
          stage: AndroidUpdateStage.ready,
          availableVersionCode: _state.availableVersionCode,
          error: error,
        ),
      );
      await AppLog.error(error, stackTrace);
      return false;
    }
  }

  void _handleInstallStatus(AndroidUpdateInstallStatus status) {
    switch (status) {
      case AndroidUpdateInstallStatus.downloaded:
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.ready,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      case AndroidUpdateInstallStatus.pending:
      case AndroidUpdateInstallStatus.downloading:
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.downloading,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      case AndroidUpdateInstallStatus.installing:
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.installing,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      case AndroidUpdateInstallStatus.installed:
        _setState(const AndroidUpdateState(stage: AndroidUpdateStage.idle));
      case AndroidUpdateInstallStatus.failed:
      case AndroidUpdateInstallStatus.canceled:
        _setState(
          AndroidUpdateState(
            stage: AndroidUpdateStage.available,
            availableVersionCode: _state.availableVersionCode,
          ),
        );
      case AndroidUpdateInstallStatus.unknown:
        break;
    }
  }

  void _setState(AndroidUpdateState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    super.dispose();
  }
}
