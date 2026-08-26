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
import 'package:leeef_reader/src/sync/background_sync_scheduler.dart';
import 'package:leeef_reader/src/tts/tts_media_controls.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--background-sync')) {
    await AppNotifications.initialize();
    await runConfiguredBackgroundSync();
    return;
  }
  await AppProxy.initialize();
  await AppLog.initialize();
  await AppNotifications.initialize();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppLog.error(details.exception, details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(AppLog.error(error, stackTrace));
    return true;
  };
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    await TtsMediaControlBridge.initialize();
  }
  await BackgroundSyncScheduler.initialize();
  await initializeDesktopWindow();
  runApp(const ProviderScope(child: DesktopWindowStateHost(child: LeeefApp())));
}
