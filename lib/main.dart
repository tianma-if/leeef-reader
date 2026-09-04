import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:leeef_reader/src/app.dart';
import 'package:leeef_reader/src/platform/desktop_window_state.dart';
import 'package:leeef_reader/src/platform/app_log.dart';
import 'package:leeef_reader/src/platform/app_proxy.dart';
import 'package:leeef_reader/src/platform/app_notifications.dart';
import 'package:leeef_reader/src/platform/app_startup.dart';
import 'package:leeef_reader/src/sync/background_sync_scheduler.dart';
import 'package:leeef_reader/src/tts/tts_media_controls.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppLog.error(details.exception, details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(AppLog.error(error, stackTrace));
    return true;
  };
  if (arguments.contains('--background-sync')) {
    await AppNotifications.initialize();
    await runConfiguredBackgroundSync();
    return;
  }
  await initializeDesktopWindow();
  runApp(
    ProviderScope(
      child: AppStartupHost(
        initialize: _initializeForegroundServices,
        child: const DesktopWindowStateHost(child: LeeefApp()),
      ),
    ),
  );
}

Future<void> _initializeForegroundServices() => runStartupInitializers(
  [
    StartupInitializer('network proxy', AppProxy.initialize),
    StartupInitializer('application log', AppLog.initialize),
    StartupInitializer('notifications', AppNotifications.initialize),
    if (Platform.isAndroid || Platform.isMacOS)
      StartupInitializer('media controls', TtsMediaControlBridge.initialize),
    StartupInitializer('background sync', BackgroundSyncScheduler.initialize),
  ],
  onError: (service, error, stackTrace) async {
    final message = '$service initialization failed: $error';
    debugPrint(message);
    await AppLog.error(message, stackTrace);
  },
);
