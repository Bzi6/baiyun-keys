import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const BaiyunKeysApp());
}

class BaiyunKeysApp extends StatelessWidget {
  const BaiyunKeysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '包子的key',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
