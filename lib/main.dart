import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'package:google_fonts/google_fonts.dart';

// App color constants
const _bgColor = Color(0xFF071226); // deep navy used in app
const _surfaceColor = Color(0xFF0F2130);
const _primaryViolet = Color(0xFF7C3AED);
const _accentCyan = Color(0xFF06B6D4);

void main() {
  runApp(const NeuroVisionApp());
}

class NeuroVisionApp extends StatelessWidget {
  const NeuroVisionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primaryViolet,
      onPrimary: Colors.white,
      secondary: _accentCyan,
      onSecondary: Colors.black,
      error: Colors.red.shade400,
      onError: Colors.white,
      background: _bgColor,
      onBackground: Colors.white70,
      surface: _surfaceColor,
      onSurface: Colors.white70,
      tertiary: _accentCyan,
      onTertiary: Colors.black,
    );

    final base = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _bgColor,
      canvasColor: _surfaceColor,
      cardColor: _surfaceColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _surfaceColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: _primaryViolet),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: _primaryViolet, foregroundColor: Colors.white),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(bodyColor: Colors.white, displayColor: Colors.white),
    );

    return MaterialApp(
      title: 'NeuroVision',
      theme: base,
      home: const HomeScreen(),
    );
  }
}
