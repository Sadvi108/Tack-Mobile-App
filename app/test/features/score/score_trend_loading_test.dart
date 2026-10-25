import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/profile/data/profile.dart';
import 'package:tack/features/profile/data/profile_repository.dart';
import 'package:tack/features/score/data/readiness.dart';
import 'package:tack/features/score/data/score_repository.dart';
import 'package:tack/features/score/presentation/score_screen.dart';

import '../../helpers.dart';

/// The trend card said "Your trend appears once you have a few days of
/// history" while the history was still on its way, then swapped to a
/// ninety-day chart. Not loaded is not empty.
void main() {
  setUpAll(loadTackFonts);

  testWidgets('a trend still loading is not called too short', (tester) async {
    await pumpAt(
      tester,
      const ScoreScreen(),
      size: const Size(360, 900),
      overrides: [
        readinessProvider.overrideWith((ref) async => ReadinessScore.empty),
        scoreTrendProvider.overrideWith((ref) => Completer<Never>().future),
        cohortProvider.overrideWith((ref) async => null),
        weekChangeProvider.overrideWith((ref) async => 0),
        modeProvider.overrideWith((ref) => YearMode.launch),
      ],
    );
    await tester.pump();

    expect(find.textContaining('Your trend appears'), findsNothing);
    expect(find.byType(TackSkeleton), findsWidgets);
  });

  testWidgets('a trend that really is short says so', (tester) async {
    await pumpAt(
      tester,
      const ScoreScreen(),
      size: const Size(360, 900),
      overrides: [
        readinessProvider.overrideWith((ref) async => ReadinessScore.empty),
        scoreTrendProvider.overrideWith((ref) async => const []),
        cohortProvider.overrideWith((ref) async => null),
        weekChangeProvider.overrideWith((ref) async => 0),
        modeProvider.overrideWith((ref) => YearMode.launch),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Your trend appears'), findsOneWidget);
  });
}
