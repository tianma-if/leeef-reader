import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

bool get isDesktopPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> initializeDesktopWindow() async {
  if (!isDesktopPlatform) return;
  await windowManager.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final width = preferences.getDouble('leeef.window.width') ?? 1180;
  final height = preferences.getDouble('leeef.window.height') ?? 760;
  final x = preferences.getDouble('leeef.window.x');
  final y = preferences.getDouble('leeef.window.y');
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(width.clamp(720, 3840), height.clamp(520, 2160)),
      minimumSize: const Size(720, 520),
      center: x == null || y == null,
      title: 'Leeef Reader',
    ),
    () async {
      if (x != null && y != null) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, width, height));
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

class DesktopWindowStateHost extends StatefulWidget {
  const DesktopWindowStateHost({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopWindowStateHost> createState() => _DesktopWindowStateHostState();
}

class _DesktopWindowStateHostState extends State<DesktopWindowStateHost>
    with WindowListener {
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) windowManager.addListener(this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (isDesktopPlatform) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMove() => _scheduleSave();
  @override
  void onWindowResize() => _scheduleSave();
  @override
  void onWindowMaximize() => _scheduleSave();
  @override
  void onWindowUnmaximize() => _scheduleSave();
  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final bounds = await windowManager.getBounds();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setDouble('leeef.window.x', bounds.left),
      preferences.setDouble('leeef.window.y', bounds.top),
      preferences.setDouble('leeef.window.width', bounds.width),
      preferences.setDouble('leeef.window.height', bounds.height),
    ]);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
