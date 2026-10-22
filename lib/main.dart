import 'package:flutter/material.dart';

import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmzyChessApp());
}

/// Emzy Chess: offline Stockfish play, local Wi-Fi P2P, and game analysis.
class EmzyChessApp extends StatelessWidget {
  const EmzyChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emzy Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5D4037),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5D4037),
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
