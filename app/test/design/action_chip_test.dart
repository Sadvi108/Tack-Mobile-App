import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';

import '../helpers.dart';

Future<void> _pump(WidgetTester tester, Widget child) => pumpAt(
  tester,
  Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
  size: const Size(360, 640),
);

void main() {
  setUpAll(loadTackFonts);

  testWidgets('it is at least 44px tall', (tester) async {
    await _pump(tester, TackActionChip('See your score', onTap: () {}));
    final size = tester.getSize(find.byType(TackActionChip));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('a screen reader hears a button with its label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, TackActionChip('Open your roadmap', onTap: () {}));
    expect(
      tester.getSemantics(find.byType(TackActionChip)),
      matchesSemantics(
        label: 'Open your roadmap',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a tap fires', (tester) async {
    var taps = 0;
    await _pump(tester, TackActionChip('Check your CV', onTap: () => taps++));
    await tester.tap(find.text('Check your CV'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('three chips wrap at 360px without overflow', (tester) async {
    await _pump(
      tester,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in [
            'Practise an interview',
            'Read about Development programme associate',
            'Check a job description',
          ])
            TackActionChip(label, onTap: () {}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
