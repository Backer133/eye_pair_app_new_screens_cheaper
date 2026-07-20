import 'package:flutter/material.dart';
import 'ble_service.dart';
import 'theme.dart';
import 'screens/discovery.dart';

void main() {
  runApp(const EyePairApp());
}

class EyePairApp extends StatefulWidget {
  const EyePairApp({super.key});
  @override
  State<EyePairApp> createState() => _EyePairAppState();
}

class _EyePairAppState extends State<EyePairApp> {
  final ble = EyeBle();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SBP Eye Settings',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: buildDarkTheme(),
      theme: buildDarkTheme(),
      home: DiscoveryScreen(ble: ble),
    );
  }
}
