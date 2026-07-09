@TestOn('browser')
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigames_firebase/minigames_firebase.dart';
import 'package:minigames_test/conformance.dart';

/// Runs the shared GameTransport conformance suite against a real Firebase
/// Realtime Database — the emulator.
///
/// Prerequisites (see repo README): a running database emulator on
/// 127.0.0.1:9000. Run with:
///
///   flutter test --platform chrome \
///     packages/minigames_firebase/test/firebase_emulator_conformance_test.dart
///
/// Tagged `browser` so the default VM `flutter test` skips it (Firebase needs a
/// platform runtime).
void main() {
  late FirebaseDatabase db;

  setUpAll(() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:1234567890:web:demo',
        messagingSenderId: '1234567890',
        projectId: 'demo-minigames',
        databaseURL: 'https://demo-minigames-default-rtdb.firebaseio.com',
      ),
    );
    db = FirebaseDatabase.instance;
    db.useDatabaseEmulator('127.0.0.1', 9000);
  });

  test(
    'FirebaseGameTransport satisfies the GameTransport conformance suite',
    () async {
      await verifyGameTransportConformance(
        createTransport: () =>
            FirebaseGameTransport(database: db, rootPath: 'conformance'),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
