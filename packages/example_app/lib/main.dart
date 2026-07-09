import 'package:flutter/material.dart';

import 'audio/demo_sfx.dart';
import 'screens/home_menu_screen.dart';
import 'theme/demo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail-soft: tests / platforms without audio still boot.
  await DemoSfx.instance.init();
  runApp(const ExampleApp());
}

/// Standalone catalog of flutter_minigames — local hot-seat play for every
/// shipped game, with a [PlaySession] / [TransportFactory] seam ready for
/// multiplayer hosts (the host app, third parties) later.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_minigames',
      debugShowCheckedModeBanner: false,
      theme: buildDemoTheme(),
      home: const HomeMenuScreen(),
    );
  }
}
