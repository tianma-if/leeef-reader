import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppNotifications {
  AppNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize({bool requestPermission = false}) async {
    if (Platform.isLinux) return;
    if (!_initialized) {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Leeef Reader',
          appUserModelId: 'Leeef.Reader.Desktop',
          guid: '39b46e39-b63f-4a95-9289-0d948ab4c81e',
        ),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    }
    if (requestPermission) await requestPermissions();
  }

  static Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static Future<void> showSyncCompleted({
    required int uploaded,
    required int downloaded,
    required int downloadedBooks,
  }) async {
    await initialize();
    if (Platform.isLinux) return;
    await _plugin.show(
      id: 0x1eeef,
      title: 'Leeef Reader · 同步完成',
      body: '上传 $uploaded，接收 $downloaded，下载 $downloadedBooks 本书',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'leeef_sync',
          '书库同步',
          channelDescription: '显示 Leeef 书库后台同步结果',
          importance: Importance.low,
          priority: Priority.low,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
    );
  }
}
