import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'connected.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: const FirebaseOptions(
    apiKey: 'AIzaSyCJFkbPCut9WUiEnQ3rFaQaqkVVRuEPVxk',
    appId: '1:166364616941:android:d71697186741571a6014e4',
    messagingSenderId: '166364616941',
    projectId: 'riogram-941b6',
    storageBucket: 'riogram-941b6.firebasestorage.app',
  ));
  runApp(const RiogramApp());
}

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
