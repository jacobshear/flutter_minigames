import 'package:flutter/material.dart';
import 'package:flutter_minigames/flutter_minigames.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _grid({required bool clocked}) {
  final tiles = Directionality(
    textDirection: TextDirection.ltr,
    child: Wrap(
      children: [
        for (final kind in GameTileKind.values)
          SizedBox(width: 60, height: 60, child: GameTileArt(kind: kind)),
      ],
    ),
  );
  return clocked ? TileArtClock(child: tiles) : tiles;
}

void main() {
  testWidgets('without a clock every tile runs its own ticker', (tester) async {
    await tester.pumpWidget(_grid(clocked: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.binding.transientCallbackCount,
      GameTileKind.values.length,
    );
  });

  testWidgets('under a TileArtClock the whole grid runs ONE ticker',
      (tester) async {
    await tester.pumpWidget(_grid(clocked: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 1);
  });

  testWidgets('the clock publishes at its fps, not at display rate',
      (tester) async {
    var repaints = 0;
    late TileArtDriver driver;
    await tester.pumpWidget(
      TileArtClock(
        child: _Probe(
          onDriver: (d) => driver = d,
          onTick: () => repaints++,
        ),
      ),
    );
    // One second of 120Hz frames.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    expect(repaints, inInclusiveRange(28, 31));
    expect(driver.value, inInclusiveRange(0.0, 1.0));
  });
}

class _Probe extends StatefulWidget {
  final void Function(TileArtDriver) onDriver;
  final VoidCallback onTick;

  const _Probe({required this.onDriver, required this.onTick});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with SingleTickerProviderStateMixin {
  late final TileArtDriver _driver = TileArtDriver(
    vsync: this,
    period: const Duration(seconds: 4),
  )..addListener(() => widget.onTick());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _driver.attach(context);
    widget.onDriver(_driver);
  }

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
