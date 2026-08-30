import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:leeef_reader/src/platform/app_log.dart';

enum DesktopUpdateStage {
  unsupported,
  idle,
  checking,
  downloading,
  ready,
  failed,
}

@immutable
class DesktopUpdateState {
  const DesktopUpdateState({required this.stage, this.version, this.error});

  const DesktopUpdateState.unsupported()
    : this(stage: DesktopUpdateStage.unsupported);

  final DesktopUpdateStage stage;
  final String? version;
  final Object? error;

  bool get isReady => stage == DesktopUpdateStage.ready;
}

abstract interface class DesktopAutoUpdateDriver {
  void addListener(UpdaterListener listener);
  void removeListener(UpdaterListener listener);
  Future<void> setFeedURL(String feedUrl);
  Future<void> setScheduledCheckInterval(int seconds);
  Future<void> checkInBackground();
  Future<bool> installDownloadedUpdate();
}

class SparkleAutoUpdateDriver implements DesktopAutoUpdateDriver {
  static const _channel = MethodChannel('dev.leanflutter.plugins/auto_updater');

  @override
  void addListener(UpdaterListener listener) =>
      autoUpdater.addListener(listener);

  @override
  void removeListener(UpdaterListener listener) =>
      autoUpdater.removeListener(listener);

  @override
  Future<void> setFeedURL(String feedUrl) => autoUpdater.setFeedURL(feedUrl);

  @override
  Future<void> setScheduledCheckInterval(int seconds) =>
      autoUpdater.setScheduledCheckInterval(seconds);

  @override
  Future<void> checkInBackground() =>
      autoUpdater.checkForUpdates(inBackground: true);

  @override
  Future<bool> installDownloadedUpdate() async =>
      await _channel.invokeMethod<bool>('installDownloadedUpdate') ?? false;
}

class DesktopAutoUpdateService extends ChangeNotifier
    implements UpdaterListener {
  DesktopAutoUpdateService({DesktopAutoUpdateDriver? driver})
    : _driver = driver ?? SparkleAutoUpdateDriver();

  static final instance = DesktopAutoUpdateService();
  static const feedUrl =
      'https://github.com/tianma-if/leeef-reader/releases/latest/download/appcast.xml';
  static const checkInterval = Duration(hours: 6);

  final DesktopAutoUpdateDriver _driver;
  var _initialized = false;
  var _enabled = false;
  var _state = const DesktopUpdateState.unsupported();

  DesktopUpdateState get state => _state;

  Future<void> initialize({bool? enabled}) async {
    if (_initialized) return;
    _initialized = true;
    final shouldEnable = enabled ?? (Platform.isMacOS && kReleaseMode);
    if (!shouldEnable) return;
    _enabled = true;

    _driver.addListener(this);
    try {
      await _driver.setFeedURL(feedUrl);
      await _driver.setScheduledCheckInterval(checkInterval.inSeconds);
      await checkNow();
    } on Object catch (error, stackTrace) {
      _setState(
        DesktopUpdateState(stage: DesktopUpdateStage.failed, error: error),
      );
      await AppLog.error(error, stackTrace);
    }
  }

  Future<void> checkNow() async {
    if (!_enabled || _state.isReady) return;
    _setState(
      DesktopUpdateState(
        stage: DesktopUpdateStage.checking,
        version: _state.version,
      ),
    );
    try {
      await _driver.checkInBackground();
    } on Object catch (error, stackTrace) {
      _setState(
        DesktopUpdateState(stage: DesktopUpdateStage.failed, error: error),
      );
      await AppLog.error(error, stackTrace);
    }
  }

  Future<bool> installDownloadedUpdate() async {
    if (!_state.isReady) return false;
    try {
      return await _driver.installDownloadedUpdate();
    } on Object catch (error, stackTrace) {
      _setState(
        DesktopUpdateState(
          stage: DesktopUpdateStage.failed,
          version: _state.version,
          error: error,
        ),
      );
      await AppLog.error(error, stackTrace);
      return false;
    }
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _setState(
      DesktopUpdateState(
        stage: DesktopUpdateStage.checking,
        version: _state.version,
      ),
    );
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _setState(
      DesktopUpdateState(
        stage: DesktopUpdateStage.downloading,
        version: _displayVersion(appcastItem),
      ),
    );
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _setState(
      DesktopUpdateState(
        stage: DesktopUpdateStage.ready,
        version: _displayVersion(appcastItem) ?? _state.version,
      ),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _setState(const DesktopUpdateState(stage: DesktopUpdateStage.idle));
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    // The patched macOS driver follows this event with update-downloaded after
    // Sparkle has exposed its immediate, verified install handoff.
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _setState(
      DesktopUpdateState(stage: DesktopUpdateStage.failed, error: error),
    );
    if (error != null) unawaited(AppLog.error(error, StackTrace.current));
  }

  String? _displayVersion(AppcastItem? item) {
    final version = item?.displayVersionString ?? item?.versionString;
    return version == null || version.trim().isEmpty ? null : version.trim();
  }

  void _setState(DesktopUpdateState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_initialized) _driver.removeListener(this);
    super.dispose();
  }
}
