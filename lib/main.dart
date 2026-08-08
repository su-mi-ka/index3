import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const FileSyncApp());
}

class FileSyncApp extends StatelessWidget {
  const FileSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '整理整頓',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
