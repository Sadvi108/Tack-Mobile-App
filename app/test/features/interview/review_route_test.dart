import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/interview/application/interview.dart';
import 'package:tack/features/interview/presentation/interview_screen.dart';
import 'package:tack/routing/routes.dart';

import '../../helpers.dart';

const _due = [
  DueQuestion(
    questionId: 'q1',
    role: 'Data analyst',
    question: 'Tell me about a time you cleaned messy data.',
    answerText: 'I fixed a sales sheet with duplicate rows.',
    keyPoints: ['Says what the problem was', 'Gives the result'],
  ),
];

/// The app's own shape: /interview, with review as its child.
Future<GoRouter> _pump(WidgetTester tester, List<DueQuestion> due) async {
  tester.view.physicalSize = shortAndroid;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: Routes.interviewReview,
    routes: [
      GoRoute(
        path: Routes.interview,
        builder: (_, _) => const InterviewScreen(),
        routes: [
          GoRoute(path: 'review', builder: (_, _) => const InterviewScreen()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dueQuestionsProvider.overrideWith((ref) async => due),
        interviewCatalogProvider.overrideWith(
          (ref) async => InterviewCatalog.empty,
        ),
        interviewHistoryProvider.overrideWith((ref) async => const []),
        companyPacksProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp.router(theme: buildTackTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUpAll(loadTackFonts);

  testWidgets('the review route opens straight into Practise again', (
    tester,
  ) async {
    await _pump(tester, _due);
    expect(
      find.text('Tell me about a time you cleaned messy data.'),
      findsOneWidget,
    );
    expect(find.text('Show my notes'), findsOneWidget);
    expect(find.text('Interview practice'), findsNothing);
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('with nothing due it says what to do', (tester) async {
    final router = await _pump(tester, const []);
    expect(find.text('Practise an interview first'), findsOneWidget);
    expect(
      find.text(
        'Answers you practise come back here after a few days, so you can try '
        'them again for free.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Start practising'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.interview,
    );
    expect(find.text('Interview practice'), findsOneWidget);
  });

  testWidgets('back lands on interview setup, not a second review', (
    tester,
  ) async {
    final router = await _pump(tester, _due);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.interview,
    );
    // The setup page under it read its own matched location, so it is setup.
    expect(find.text('Interview practice'), findsOneWidget);
    expect(find.text('Show my notes'), findsNothing);
  });
}
