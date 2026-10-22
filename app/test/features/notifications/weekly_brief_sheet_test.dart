import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';
import 'package:tack/features/notifications/presentation/weekly_brief_sheet.dart';

import '../../helpers.dart';

const _items = [
  BriefItem(
    title: 'Meghna Foods closes Wed 28 Oct',
    why: 'Send your application before then, or let it go. Either is fine.',
    route: '/applications/abc',
  ),
  BriefItem(
    title: 'Padma Textiles interview, Thu 29 Oct',
    why: 'Practise three questions for this role before the day.',
    route: '/applications/def',
  ),
  BriefItem(
    title: '2 roadmap steps are late',
    why: 'Move a date or tick one off. Nothing is lost.',
    route: '/roadmap',
  ),
];

void main() {
  setUpAll(loadTackFonts);

  testWidgets('shows every item and why it matters, at 360 wide', (
    tester,
  ) async {
    await pumpAt(
      tester,
      Scaffold(
        body: WeeklyBriefSheet(items: _items, onOpen: (_) {}),
      ),
    );

    for (final item in _items) {
      expect(find.text(item.title), findsOneWidget);
      expect(find.text(item.why), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('still fits at twice the text size on a short phone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            // The sheet caps its own height at 82% of the screen.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: shortAndroid.height * 0.82,
              ),
              child: WeeklyBriefSheet(items: _items, onOpen: (_) {}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text(_items.last.why), 200);
    expect(find.text(_items.last.why), findsOneWidget);
  });

  testWidgets('tapping an item opens where it points', (tester) async {
    String? opened;
    await pumpAt(
      tester,
      Scaffold(
        body: WeeklyBriefSheet(items: _items, onOpen: (r) => opened = r),
      ),
    );

    await tester.tap(find.text('Padma Textiles interview, Thu 29 Oct'));
    await tester.pumpAndSettle();

    expect(opened, '/applications/def');
  });
}
