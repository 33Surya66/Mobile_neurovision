import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/landing_page.dart';

// App color constants
const _bgColor = Color(0xFF071226); // deep navy used in app
const _surfaceColor = Color(0xFF0F2130);
const _primaryViolet = Color(0xFF7C3AED);
const _accentCyan = Color(0xFF06B6D4);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryViolet,
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryViolet,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 2,
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    return MaterialApp(
      title: 'NeuroVision',
      theme: base,
      home: const LandingPage(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/landing': (context) => const LandingPage(),
      },
    );
  }
}
