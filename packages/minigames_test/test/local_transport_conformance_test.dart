import 'package:minigames_core/minigames_core.dart';
import 'package:minigames_test/minigames_test.dart';

/// Proves both the conformance kit itself and that [LocalTransport] satisfies
/// the [GameTransport] contract. Every other transport (e.g. the Firebase
/// adapter) runs this same suite.
void main() {
  runGameTransportConformanceTests(
    createTransport: LocalTransport.new,
    tearDownTransport: (t) async => (t as LocalTransport).dispose(),
  );
}
