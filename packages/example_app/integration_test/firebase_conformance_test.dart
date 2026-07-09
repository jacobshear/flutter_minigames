import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minigames_firebase/minigames_firebase.dart';
import 'package:minigames_test/conformance.dart';

/// Verifies [FirebaseGameTransport] against a real Realtime Database (the
/// emulator) by running the shared conformance suite.
///
/// Runs as an integration test so the native Firebase SDK is registered:
///
///   1. Start the emulator:  firebase emulators:start --only database --project demo-minigames
///   2. flutter test integration_test/firebase_conformance_test.dart -d DEVICE_ID
///
/// The iOS simulator / macOS reach the emulator on 127.0.0.1 directly.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FirebaseDatabase db;

  setUpAll(() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-api-key',
        // iOS FirebaseCore validates the app-id fingerprint as hex, so the last
        // segment must be hex digits (unlike Android/web, which are lenient).
        appId: '1:1234567890:ios:0a1b2c3d4e5f60718293',
        messagingSenderId: '1234567890',
        projectId: 'demo-minigames',
        databaseURL: 'https://demo-minigames-default-rtdb.firebaseio.com',
      ),
    );
    db = FirebaseDatabase.instance;
    db.useDatabaseEmulator('127.0.0.1', 9000);
  });

  testWidgets(
    'FirebaseGameTransport satisfies the GameTransport conformance suite',
    (tester) async {
      await verifyGameTransportConformance(
        createTransport: () =>
            FirebaseGameTransport(database: db, rootPath: 'conformance'),
      );
    },
  );
}
