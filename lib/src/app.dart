import 'package:flutter/material.dart';
import 'package:leeef_reader/src/features/library/library_screen.dart';

class LeeefApp extends StatelessWidget {
  const LeeefApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF356A45);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leeef Reader',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}
