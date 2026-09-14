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
  Color? _cachedSeed;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  @override
  void initState() {
    super.initState();
    AppAppearanceController.instance.load();
  }

  void _ensureThemes(Color seed) {
    if (_cachedSeed == seed && _lightTheme != null && _darkTheme != null) {
      return;
    }
    _cachedSeed = seed;
    _lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      useMaterial3: true,
    );
    _darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppAppearanceController.instance,
      builder: (context, _) {
        final appearance = AppAppearanceController.instance;
        _ensureThemes(appearance.seedColor);
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
          themeAnimationDuration: Duration.zero,
          theme: _lightTheme!,
          darkTheme: _darkTheme!,
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
