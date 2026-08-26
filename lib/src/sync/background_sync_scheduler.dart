import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:leeef_reader/src/data/database/app_database.dart';
import 'package:leeef_reader/src/data/repositories/library_repository.dart';
import 'package:leeef_reader/src/platform/app_notifications.dart';
import 'package:leeef_reader/src/sync/configured_sync_backend.dart';
import 'package:leeef_reader/src/sync/sync_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

const backgroundSyncTaskName = 'dev.leeef.leeefReader.backgroundSync';
const windowsBackgroundSyncTaskName = 'LeeefReaderBackgroundSync';

List<String> windowsBackgroundTaskArguments({
  required bool enabled,
  required String executable,
}) {
  if (!enabled) {
    return const ['/Delete', '/TN', windowsBackgroundSyncTaskName, '/F'];
  }
  final escapedExecutable = executable.replaceAll('"', '\\"');
  return [
    '/Create',
    '/SC',
    'MINUTE',
    '/MO',
    '30',
    '/TN',
    windowsBackgroundSyncTaskName,
    '/TR',
    '"$escapedExecutable" --background-sync',
    '/F',
  ];
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != backgroundSyncTaskName &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return runConfiguredBackgroundSync();
  });
}

@pragma('vm:entry-point')
Future<bool> runConfiguredBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool('leeef.storage.database_restart_pending') ?? false) {
    return true;
  }
  if (!(preferences.getBool('leeef.sync.auto') ?? true)) return true;
  final connectivity = await Connectivity().checkConnectivity();
  if (connectivity.contains(ConnectivityResult.none)) return false;
  if ((preferences.getBool('leeef.sync.wifi_only') ?? false) &&
      !connectivity.contains(ConnectivityResult.wifi) &&
      !connectivity.contains(ConnectivityResult.ethernet)) {
    return true;
  }
  final database = AppDatabase();
  try {
    var deviceId = preferences.getString('leeef.device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v7();
      await preferences.setString('leeef.device_id', deviceId);
    }
    final repository = LibraryRepository(
      database: database,
      deviceId: deviceId,
    );
    final documents = await getApplicationDocumentsDirectory();
    final customDirectory = preferences.getString(
      'leeef.storage.custom_directory',
    );
    final report = await SyncEngine(
      repository: repository,
      backend: await loadConfiguredSyncBackend(),
      libraryDirectory: customDirectory == null || customDirectory.isEmpty
          ? Directory('${documents.path}/leeef/books')
          : Directory(customDirectory),
    ).synchronize();
    if (preferences.getBool('leeef.sync.completion_notifications') ?? true) {
      await AppNotifications.showSyncCompleted(
        uploaded: report.uploadedOperations,
        downloaded: report.downloadedOperations,
        downloadedBooks: report.downloadedBooks,
      );
    }
    return true;
  } on Object {
    return false;
  } finally {
    await database.close();
  }
}

class BackgroundSyncScheduler {
  const BackgroundSyncScheduler._();

  static bool get supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  static Future<void> initialize() async {
    if (!supported) return;
    if (Platform.isWindows) {
      final preferences = await SharedPreferences.getInstance();
      await configure(
        enabled: preferences.getBool('leeef.sync.auto') ?? true,
        wifiOnly: preferences.getBool('leeef.sync.wifi_only') ?? false,
      );
      return;
    }
    await Workmanager().initialize(callbackDispatcher);
    final preferences = await SharedPreferences.getInstance();
    await configure(
      enabled: preferences.getBool('leeef.sync.auto') ?? true,
      wifiOnly: preferences.getBool('leeef.sync.wifi_only') ?? false,
    );
  }

  static Future<void> configure({
    required bool enabled,
    required bool wifiOnly,
  }) async {
    if (!supported) return;
    if (Platform.isWindows) {
      await _configureWindowsTask(enabled);
      return;
    }
    if (!enabled) {
      await Workmanager().cancelByUniqueName(backgroundSyncTaskName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      backgroundSyncTaskName,
      backgroundSyncTaskName,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
    );
  }

  static Future<void> _configureWindowsTask(bool enabled) async {
    final executable = Platform.resolvedExecutable;
    if (!enabled) {
      await Process.run(
        'schtasks.exe',
        windowsBackgroundTaskArguments(enabled: false, executable: executable),
      );
      return;
    }
    if (!await File(executable).exists()) return;
    final result = await Process.run(
      'schtasks.exe',
      windowsBackgroundTaskArguments(enabled: true, executable: executable),
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Windows background task registration failed: ${result.stderr}',
      );
    }
  }
}
