import 'package:flutter/material.dart';

import 'audio/demo_sfx.dart';
import 'screens/home_menu_screen.dart';
import 'theme/demo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DemoSfx.instance.init();
  runApp(const ExampleApp());
}

/// Standalone full-screen demo of the minigames launcher (GamePigeon-style
/// grid). A host app re-uses [gameCatalog],
/// [PlaySession], and the same play screens — without this MaterialApp shell.
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
