// The to-do card on the dashboard. A roadmap step can be ticked where it
// stands; anything else can only be opened. The two used to look identical —
// an empty checkbox on "Add your CGPA" that did nothing when pressed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/dashboard/application/next_actions.dart';
import 'package:tack/features/dashboard/presentation/widgets.dart';

const _task = NextAction(
  title: 'Finish the take-home',
  points: 6,
  effortMinutes: 60,
  route: '/roadmap',
  taskId: 't1',
);

const _profileItem = NextAction(
  title: 'Add your CGPA',
  points: 6,
  effortMinutes: 2,
  route: '/profile',
);

Future<(List<NextAction>, List<NextAction>)> _pump(WidgetTester tester) async {
  final opened = <NextAction>[];
  final ticked = <NextAction>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: NextThreeActions(
            actions: const [_task, _profileItem],
            onOpen: opened.add,
            onTickTask: ticked.add,
          ),
        ),
      ),
    ),
  );
  return (opened, ticked);
}

void main() {
  testWidgets('a step ticks once, and shows it straight away', (tester) async {
    final semantics = tester.ensureSemantics();
    final (opened, ticked) = await _pump(tester);
    final box = find.bySemanticsLabel('Mark Finish the take-home as done');

    expect(
      tester.getSemantics(box),
      isSemantics(isButton: true, hasCheckedState: true, isChecked: false),
    );

    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(ticked, [_task]);
    expect(opened, isEmpty, reason: 'ticking must not also open the step');
    expect(
      tester.getSemantics(box),
      isSemantics(isChecked: true),
      reason: 'the tick shows before the write lands, not after',
    );

    // A second tap while the feed reloads must not write twice.
    await tester.tap(box);
    await tester.pumpAndSettle();
    expect(ticked, [_task]);
    semantics.dispose();
  });

  testWidgets('the tick box is a full 44px target', (tester) async {
    await _pump(tester);
    final size = tester.getSize(
      find
          .ancestor(
            of: find.byType(AnimatedContainer),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(size.width, greaterThanOrEqualTo(TackSpace.tapTarget));
    expect(size.height, greaterThanOrEqualTo(TackSpace.tapTarget));
  });

  testWidgets('something to add has no checkbox to tick', (tester) async {
    final semantics = tester.ensureSemantics();
    final (opened, ticked) = await _pump(tester);

    expect(find.bySemanticsLabel('Mark Add your CGPA as done'), findsNothing);

    await tester.tap(find.text('Add your CGPA'));
    await tester.pumpAndSettle();
    expect(opened, [_profileItem]);
    expect(ticked, isEmpty);
    semantics.dispose();
  });
}
