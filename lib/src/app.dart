import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/library/library_screen.dart';
import 'package:leeef_reader/src/platform/android_update_host.dart';
import 'package:leeef_reader/src/sync/automatic_sync_host.dart';
import 'package:leeef_reader/src/platform/app_appearance.dart';
import 'package:leeef_reader/src/platform/desktop_update_host.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:leeef_reader/src/features/onboarding/onboarding_host.dart';

class LeeefApp extends StatefulWidget {
  const LeeefApp({super.key});

  @override
  State<LeeefApp> createState() => _LeeefAppState();
}

class _LeeefAppState extends State<LeeefApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    AppAppearanceController.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppAppearanceController.instance,
      builder: (context, _) {
        final appearance = AppAppearanceController.instance;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messengerKey,
          title: 'Leeef Reader',
          locale: appearance.locale,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: appearance.themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: appearance.seedColor),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: appearance.seedColor,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: AndroidUpdateHost(
            child: DesktopUpdateHost(
              child: OnboardingHost(
                child: AutomaticSyncHost(
                  onCompleted: (report) => _messengerKey.currentState?.showSnackBar(
                    SnackBar(
                      content: Text(
                        '自动同步完成：上传 ${report.uploadedOperations}，接收 ${report.downloadedOperations}，下载 ${report.downloadedBooks} 本，配置 ${report.trustedSync?.appliedConfigurationValues ?? 0} 项',
                      ),
                    ),
                  ),
                  child: const LibraryScreen(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
