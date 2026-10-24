import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/applications/data/checklist_models.dart';
import 'package:tack/features/applications/presentation/checklist_card.dart';
import 'package:tack/features/applications/presentation/prep_brief_card.dart';

import '../../helpers.dart';

final _checklist = Checklist.fromJson({
  'items': [
    {
      'id': 'APP-PRACTICE',
      'severity': 'required',
      'action': 'practise',
      'title': 'Practise a few questions for this role this week',
    },
    {
      'id': 'APP-PREP',
      'severity': 'recommended',
      'action': 'prep',
      'title': 'Get your interview prep brief',
    },
    {
      'id': 'APP-CV',
      'severity': 'recommended',
      'action': 'attach_cv',
      'title': 'Attach the CV you sent',
    },
  ],
  'next_step': {
    'id': 'APP-PRACTICE',
    'severity': 'required',
    'action': 'practise',
    'title': 'Practise a few questions for this role this week',
  },
});

final _brief = PrepBrief.fromJson({
  'talking_points': [
    {
      'point': 'You can build their weekly dashboards',
      'evidence': 'Your shop sales dashboard does this for a real shop',
    },
    {
      'point': 'You are comfortable with their data',
      'evidence': 'You list SQL and Excel',
    },
  ],
  'likely_questions': [
    {
      'question': 'Tell me about a dashboard you built.',
      'why': 'The role is mostly dashboards.',
    },
  ],
  'questions_to_ask': ['Who reads the weekly dashboard?'],
  'gaps': [
    {
      'skill': 'Power BI',
      'how_to_prepare': 'Rebuild your shop dashboard in the free version.',
    },
  ],
})!;

void main() {
  setUpAll(loadTackFonts);

  group('the checklist card', () {
    testWidgets('leads with the next step, then the rest', (tester) async {
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: ChecklistCard(checklist: _checklist, onAction: (_) {}),
          ),
        ),
      );

      expect(find.text('Next step'), findsOneWidget);
      final next = tester.getTopLeft(
        find.text('Practise a few questions for this role this week'),
      );
      final later = tester.getTopLeft(find.text('Attach the CV you sent'));
      expect(next.dy, lessThan(later.dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an item asks for its action', (tester) async {
      ChecklistItem? tapped;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: ChecklistCard(
              checklist: _checklist,
              onAction: (item) => tapped = item,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Attach the CV you sent'));
      expect(tapped?.action, ChecklistAction.attachCv);
    });

    testWidgets('an empty checklist takes no space', (tester) async {
      await pumpAt(
        tester,
        Scaffold(
          body: ChecklistCard(
            checklist: Checklist.fromJson({'items': [], 'next_step': null}),
            onAction: (_) {},
          ),
        ),
      );
      expect(find.text('Next step'), findsNothing);
    });
  });

  group('the prep brief card', () {
    testWidgets('before a brief, offers one and says what it costs', (
      tester,
    ) async {
      var asked = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PrepBriefCard(brief: null, onRequest: () => asked++),
          ),
        ),
      );

      expect(find.textContaining('one AI action'), findsOneWidget);
      await tester.tap(find.text('Get your prep brief'));
      expect(asked, 1);
    });

    testWidgets('shows every section, each point with its proof', (
      tester,
    ) async {
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PrepBriefCard(brief: _brief, onRequest: () {}),
          ),
        ),
      );

      expect(
        find.text('You can build their weekly dashboards'),
        findsOneWidget,
      );
      expect(
        find.text('Proof: Your shop sales dashboard does this for a real shop'),
        findsOneWidget,
      );
      expect(find.text('Tell me about a dashboard you built.'), findsOneWidget);
      expect(find.text('Who reads the weekly dashboard?'), findsOneWidget);
      expect(find.text('Power BI'), findsOneWidget);
      expect(find.text('Get your prep brief'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a brief can be refreshed after the profile changes', (
      tester,
    ) async {
      var asked = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PrepBriefCard(brief: _brief, onRequest: () => asked++),
          ),
        ),
      );

      await tester.scrollUntilVisible(find.text('Refresh brief'), 200);
      expect(
        find.textContaining('Free if nothing has changed'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh brief'));
      expect(asked, 1);
    });

    testWidgets('while it is being written, says so and cannot be re-sent', (
      tester,
    ) async {
      var asked = 0;
      await pumpAt(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: PrepBriefCard(
              brief: null,
              busy: true,
              onRequest: () => asked++,
            ),
          ),
        ),
      );

      expect(find.textContaining('Writing your brief'), findsOneWidget);
      await tester.tap(find.textContaining('Writing your brief'));
      expect(asked, 0);
    });
  });
}
