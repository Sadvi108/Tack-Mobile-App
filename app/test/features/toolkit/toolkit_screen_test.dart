import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/core/ai/allowance.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/interview/data/interview_models.dart';
import 'package:tack/features/toolkit/application/toolkit_analytics.dart';
import 'package:tack/features/toolkit/application/toolkit_status.dart';
import 'package:tack/features/toolkit/application/toolkit_tools.dart';
import 'package:tack/features/toolkit/presentation/tool_card.dart';
import 'package:tack/features/toolkit/presentation/toolkit_screen.dart';
import 'package:tack/features/vault/application/cv_check.dart';
import 'package:tack/routing/router.dart';

import '../../helpers.dart';

TackDocument _doc(String id, DocumentType type, String mime) => TackDocument(
  id: id,
  type: type,
  title: id,
  storagePath: 'users/u/$id',
  status: DocumentStatus.ready,
  mimeType: mime,
  createdAt: DateTime(2026, 11),
);

final _pdfCv = _doc('cv', DocumentType.cv, 'application/pdf');
final _jpgCv = _doc('photo-cv', DocumentType.cv, 'image/jpeg');
final _certificate = _doc('cert', DocumentType.certificate, 'image/png');

List<DueQuestion> _due(int n) => [
  for (var i = 0; i < n; i++)
    DueQuestion(questionId: 'q$i', role: 'data-analyst', question: 'Q$i'),
];

typedef _Opened = (ToolkitTool, ToolSource, int?);

/// Pumps the hub inside a stub router so taps can be followed.
Future<GoRouter> _pump(
  WidgetTester tester, {
  YearMode mode = YearMode.launch,
  Object documents = const <TackDocument>[],
  int due = 0,
  Object allowance = const AiAllowance(used: 1, limit: 8),
  Size size = const Size(360, 2400),
  List<_Opened>? opened,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  Widget stub(String name) => Scaffold(body: Text('$name page'));
  final router = GoRouter(
    initialLocation: Routes.toolkit,
    routes: [
      GoRoute(path: Routes.toolkit, builder: (_, _) => const ToolkitScreen()),
      for (final location in [
        Routes.interview,
        Routes.interviewReview,
        Routes.analyser,
        Routes.cvCheck,
        Routes.cvBuilder,
        Routes.vault,
        Routes.coach,
        Routes.roadmap,
      ])
        GoRoute(path: location, builder: (_, _) => stub(location)),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modeProvider.overrideWithValue(mode),
        isOnlineProvider.overrideWithValue(true),
        pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
        documentsProvider.overrideWith((ref) async {
          if (documents is List<TackDocument>) return documents;
          throw documents;
        }),
        dueQuestionsProvider.overrideWith((ref) async => _due(due)),
        aiAllowanceProvider.overrideWith((ref) async {
          if (allowance is AiAllowance) return allowance;
          throw allowance;
        }),
        toolOpenedProvider.overrideWithValue(
          (tool, source, {count}) => opened?.add((tool, source, count)),
        ),
      ],
      child: MaterialApp.router(
        theme: buildTackTheme(TackBrightness.current),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  setUpAll(loadTackFonts);
  tearDown(() => TackBrightness.set(Brightness.light));

  group('every mode renders', () {
    for (final brightness in Brightness.values) {
      for (final height in [640.0, 800.0]) {
        for (final mode in YearMode.values) {
          testWidgets('${mode.name} at 360x${height.toInt()}, '
              '${brightness.name}', (tester) async {
            TackBrightness.set(brightness);
            await _pump(
              tester,
              mode: mode,
              documents: [_pdfCv, _certificate],
              due: 2,
              size: Size(360, height),
            );
            expect(tester.takeException(), isNull);
            expect(find.byType(ToolCard), findsWidgets);
            for (final card in tester.widgetList(find.byType(ToolCard))) {
              final size = tester.getSize(find.byWidget(card));
              expect(size.height, greaterThanOrEqualTo(44));
            }
          });
        }
      }
    }
  });

  testWidgets('a final-year starts with interview practice', (tester) async {
    await _pump(tester, mode: YearMode.launch, documents: [_pdfCv]);
    final first = tester.widget<ToolCard>(find.byType(ToolCard).first);
    expect(first.title, 'Practise for interviews');
  });

  testWidgets('explore never talks about deadlines or applying', (
    tester,
  ) async {
    await _pump(tester, mode: YearMode.explore, documents: [_certificate]);
    final banned = RegExp(
      r'\b(deadline|apply|applying|applied|applications?)\b',
      caseSensitive: false,
    );
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(matches(banned)), reason: text.data);
    }
  });

  testWidgets('answers due show up as practise again', (tester) async {
    await _pump(tester, documents: [_pdfCv], due: 3);
    expect(find.text('Practise again'), findsOneWidget);
    expect(find.text('3 answers are ready to try again.'), findsOneWidget);
  });

  testWidgets('a school student is not offered practice, the CV check or the '
      'builder', (tester) async {
    await _pump(tester, mode: YearMode.discover, documents: [_pdfCv], due: 2);
    expect(find.text('Practise'), findsNothing);
    expect(find.text('Check your CV'), findsNothing);
    expect(find.text('Start your CV'), findsNothing);
    expect(find.text('Build another CV in Tack'), findsNothing);
    expect(find.text('Ask your coach'), findsOneWidget);
  });

  testWidgets('no CV yet offers to start one', (tester) async {
    await _pump(tester, mode: YearMode.explore, documents: [_certificate]);
    expect(find.text('Start your CV'), findsOneWidget);
    expect(find.text('Check your CV'), findsNothing);
  });

  testWidgets('a PDF CV can be checked, for free', (tester) async {
    await _pump(tester, documents: [_pdfCv]);
    expect(find.text('Check your CV'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('a photo of a CV gets no check row', (tester) async {
    await _pump(tester, documents: [_jpgCv]);
    expect(find.text('Check your CV'), findsNothing);
  });

  testWidgets('documents that fail to load say so, and the rest still works', (
    tester,
  ) async {
    final opened = <_Opened>[];
    final router = await _pump(
      tester,
      documents: Exception('offline'),
      opened: opened,
    );
    expect(find.text('Your documents did not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Ask your coach'));
    await tester.pumpAndSettle();
    expect(_location(router), Routes.coach);
  });

  group('the AI allowance', () {
    testWidgets('says what is left, never the limit', (tester) async {
      await _pump(tester);
      expect(find.text('AI ACTIONS TODAY'), findsOneWidget);
      expect(
        find.text(
          '7 AI actions left today. Tools marked free never use one. More '
          'arrive at midnight.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(' of '), findsNothing);
    });

    testWidgets('spent, it explains the trade instead', (tester) async {
      await _pump(tester, allowance: const AiAllowance(used: 8, limit: 8));
      expect(find.byType(TackQuotaState), findsOneWidget);
      expect(find.text('AI ACTIONS TODAY'), findsNothing);
    });

    testWidgets('a failed read hides the note, not the screen', (tester) async {
      await _pump(tester, allowance: Exception('offline'));
      expect(find.text('AI ACTIONS TODAY'), findsNothing);
      expect(find.byType(TackQuotaState), findsNothing);
      expect(find.byType(ToolCard), findsWidgets);
    });
  });

  group('taps', () {
    testWidgets('a tool covers the bar, and back returns to the hub', (
      tester,
    ) async {
      final opened = <_Opened>[];
      final router = await _pump(tester, documents: [_pdfCv], opened: opened);

      await tester.tap(find.text('Practise for interviews'));
      await tester.pumpAndSettle();
      expect(_location(router), Routes.interview);
      expect(router.canPop(), isTrue);
      expect(opened, [(ToolkitTool.interview, ToolSource.toolkit, null)]);
    });

    testWidgets('the documents switch to the list in the same tab', (
      tester,
    ) async {
      final opened = <_Opened>[];
      final router = await _pump(tester, documents: [_pdfCv], opened: opened);

      await tester.tap(find.text('Your documents'));
      await tester.pumpAndSettle();
      expect(_location(router), Routes.vault);
      expect(router.canPop(), isFalse);
      expect(opened, [(ToolkitTool.documents, ToolSource.toolkit, null)]);
    });

    testWidgets('the CV check opens its entry route', (tester) async {
      final opened = <_Opened>[];
      final router = await _pump(tester, documents: [_pdfCv], opened: opened);

      await tester.tap(find.text('Check your CV'));
      await tester.pumpAndSettle();
      expect(_location(router), Routes.cvCheck);
      expect(opened, [(ToolkitTool.cvCheck, ToolSource.toolkit, null)]);
    });

    testWidgets('practise again records how many were due', (tester) async {
      final opened = <_Opened>[];
      final router = await _pump(
        tester,
        documents: [_pdfCv],
        due: 3,
        opened: opened,
      );

      await tester.tap(find.text('Practise again'));
      await tester.pumpAndSettle();
      expect(_location(router), Routes.interviewReview);
      expect(opened, [(ToolkitTool.practiseAgain, ToolSource.toolkit, 3)]);
    });
  });
}
