// A tappable card has to look pressed, say it is a button, and never make a
// student wait for either. These are the properties screenshots cannot see:
// they are all about what happens while a finger is down.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  VoidCallback? onTap,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: TackCard(
                  onTap: onTap,
                  child: const Text('Your roadmap'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The scale the card is currently drawn at.
double _scale(WidgetTester tester) {
  final transforms = find.descendant(
    of: find.byType(TackPressable),
    matching: find.byType(Transform),
  );
  // The x scale itself. getMaxScaleOnAxis would include z, which a 2D scale
  // leaves at 1, and so always answer 1.
  return tester.widget<Transform>(transforms.first).transform.entry(0, 0);
}

void main() {
  tearDown(() => TackBrightness.set(Brightness.light));

  testWidgets('a tappable card sinks while held and comes back after', (
    tester,
  ) async {
    var taps = 0;
    await _pumpCard(tester, onTap: () => taps++);
    expect(_scale(tester), 1);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(TackCard)),
    );
    await tester.pumpAndSettle();
    expect(_scale(tester), closeTo(TackMotion.pressScale, 0.001));
    expect(taps, 0, reason: 'a press is not a tap until the finger lifts');

    await finger.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(taps, 1);
  });

  testWidgets('a quick tap still shows, rather than lasting one frame', (
    tester,
  ) async {
    await _pumpCard(tester, onTap: () {});

    // Down and up in the same frame: the commonest tap there is.
    await tester.tap(find.byType(TackCard));
    // The first frame only starts the ticker; the second is the first to move.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_scale(tester), lessThan(1));

    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
  });

  testWidgets('with reduced motion the card does not move', (tester) async {
    await _pumpCard(tester, onTap: () {}, reduceMotion: true);

    final finger = await tester.startGesture(
      tester.getCenter(find.byType(TackCard)),
    );
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);

    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a tappable card is announced as a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpCard(tester, onTap: () {});

    expect(
      tester.getSemantics(find.byType(TackCard)),
      isSemantics(isButton: true, hasTapAction: true, isFocusable: true),
    );
    semantics.dispose();
  });

  testWidgets('a screen reader can press one that reads as a single label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TackPressable(
              onTap: () => taps++,
              semanticLabel: 'Ask your coach',
              excludeSemantics: true,
              child: const Text('Ask'),
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('Ask your coach'));
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('a card with nothing to open is not a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpCard(tester);

    expect(find.byType(TackPressable), findsNothing);
    expect(
      tester.getSemantics(find.text('Your roadmap')),
      isNot(isSemantics(isButton: true)),
    );
    semantics.dispose();
  });

  testWidgets('a keyboard or switch user can open a card', (tester) async {
    var taps = 0;
    await _pumpCard(tester, onTap: () => taps++);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(taps, 1);
  });

  group('the edge of a card', () {
    Decoration? foreground(WidgetTester tester) => tester
        .widget<Container>(
          find
              .descendant(
                of: find.byType(TackCard),
                matching: find.byType(Container),
              )
              .first,
        )
        .foregroundDecoration;

    testWidgets('is drawn in the dark, where a shadow cannot be seen', (
      tester,
    ) async {
      TackBrightness.set(Brightness.dark);
      await _pumpCard(tester);
      expect(foreground(tester), isNotNull);
    });

    // A glass pane is translucent, so in the light the shadow alone no longer
    // says where it stops: the bright rim does that in both palettes.
    testWidgets('is drawn in the light too, as the rim of the glass', (
      tester,
    ) async {
      TackBrightness.set(Brightness.light);
      await _pumpCard(tester);
      expect(foreground(tester), isNotNull);
    });

    testWidgets('is left to the maroon border on an emphasised card', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TackCard(emphasised: true, child: Text('Next three')),
          ),
        ),
      );
      expect(foreground(tester), isNull);
    });
  });
}
