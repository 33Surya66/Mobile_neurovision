import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const NeuroVisionApp());
}

class NeuroVisionApp extends StatelessWidget {
  const NeuroVisionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroVision',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
