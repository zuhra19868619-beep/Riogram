import 'package:flutter/material.dart';
import 'connected.dart';

void main() => runApp(const RiogramApp());

class RiogramApp extends StatefulWidget {
  const RiogramApp({super.key});
  @override
  State<RiogramApp> createState() => _RiogramAppState();
}

class _RiogramAppState extends State<RiogramApp> {
  ThemeMode themeMode = ThemeMode.system;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Riogram',
    debugShowCheckedModeBanner: false,
    themeMode: themeMode,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3390EC),
        surface: Colors.white),
      appBarTheme: const AppBarTheme(
        centerTitle: false, elevation: 0, backgroundColor: Colors.white,
        foregroundColor: Color(0xFF17212C)),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3390EC),
        brightness: Brightness.dark)),
    home: const ConnectedApp(),
  );
}
