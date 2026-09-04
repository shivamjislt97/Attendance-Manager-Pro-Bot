import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.loadSaved();
  runApp(const AttApp());
}


class AttApp extends StatelessWidget {
  const AttApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Manager Pro',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // force dark — system theme follow nahi
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(primary: green, surface: surface),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F2038),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: line)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        fontFamily: 'Inter',
      ),
      home: Api.token.isNotEmpty && Api.profile != null
          ? const HomeShell()
          : const LoginScreen(),
    );
  }
}

// ---------------- LOGIN ----------------
