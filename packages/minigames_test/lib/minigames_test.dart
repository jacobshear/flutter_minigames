/// `package:test` wrapper over the framework-agnostic conformance checks.
///
/// For `dart test` users, [runGameTransportConformanceTests] registers the
/// suite as a normal test case:
///
/// ```dart
/// import 'package:minigames_core/minigames_core.dart';
/// import 'package:minigames_test/minigames_test.dart';
///
/// void main() {
///   runGameTransportConformanceTests(createTransport: LocalTransport.new);
/// }
/// ```
///
/// Running under `flutter_test` / `integration_test` instead? Import
/// `package:minigames_test/conformance.dart` and call
/// [verifyGameTransportConformance] inside your own `test(...)` — it pulls in no
/// test framework, so there's no `package:test` vs `flutter_test` clash.
library;

import 'package:minigames_core/minigames_core.dart';
import 'package:test/test.dart';

import 'conformance.dart';

export 'conformance.dart';

/// Registers the [GameTransport] conformance suite as a `package:test` case.
void runGameTransportConformanceTests({
  required GameTransport Function() createTransport,
  Future<void> Function(GameTransport transport)? tearDownTransport,
}) {
  test('GameTransport conformance', () async {
    await verifyGameTransportConformance(
      createTransport: createTransport,
      tearDownTransport: tearDownTransport,
    );
  });
}
