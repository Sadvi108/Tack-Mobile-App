import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/dashboard/data/dashboard_feed.dart';
import 'package:tack/features/dashboard/presentation/streak_card.dart';

import '../../helpers.dart';

void main() {
  setUpAll(loadTackFonts);

  final today = DateTime(2026, 8, 26);

  Future<void> pumpCard(WidgetTester tester, Streak streak) async {
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: StreakCard(streak: streak, today: today),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a steady student sees their rhythm even after a quiet day', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const Streak(
        current: 0,
        longest: 6,
        days: [],
        rhythm: Rhythm(score: 72, weekChange: 4, recentDays: 3, target: 3),
      ),
    );

    expect(find.text('Rhythm'), findsOneWidget);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    expect(find.textContaining('keeps your rhythm rising'), findsOneWidget);
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('below pace says what counts, never what was lost', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const Streak(
        current: 1,
        longest: 6,
        days: [],
        rhythm: Rhythm(score: 40, weekChange: -8, recentDays: 1, target: 3),
      ),
    );

    expect(find.text('40%'), findsOneWidget);
    // A drop is not announced; the caption says what to do instead.
    expect(find.text('-8'), findsNothing);
    expect(find.textContaining('1 of 3 active days'), findsOneWidget);
  });

  testWidgets('no rhythm row before the student has done anything', (
    tester,
  ) async {
    await pumpCard(tester, Streak.empty);
    expect(find.text('Rhythm'), findsNothing);
  });
}
