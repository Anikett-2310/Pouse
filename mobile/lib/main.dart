import 'package:flutter/material.dart';
import 'src/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PouseApp());
}

class PouseApp extends StatelessWidget {
  const PouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pouse - Pocket Mouse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF1E1E24),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
