import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/applications/application/checklist.dart';
import 'package:tack/features/applications/data/application_models.dart';
import 'package:tack/features/applications/data/application_repository.dart';
import 'package:tack/features/applications/presentation/application_detail_screen.dart';

import '../../helpers.dart';

const _id = '7b0c1a52-9a52-4c7e-9a43-3f1f5d3b2a10';

const _application = JobApplication(
  id: _id,
  jobId: 'job-1',
  status: TackStatus.applied,
  title: 'Junior data analyst',
  companyName: 'Meghna Foods',
);

final _checklist = Checklist.fromJson({
  'items': [
    {
      'id': 'APP-CV',
      'severity': 'recommended',
      'action': 'attach_cv',
      'title': 'Attach the CV you sent',
    },
  ],
  'next_step': {
    'id': 'APP-CV',
    'severity': 'recommended',
    'action': 'attach_cv',
    'title': 'Attach the CV you sent',
  },
});

/// No history, and nothing reaches the network.
class _FakeRepository extends ApplicationRepository {
  _FakeRepository()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<StatusChange>> history(String applicationId) async => const [];
}

void main() {
  // Attaching a CV or moving the status reloads the application list under
  // this screen. The screen used to drop to its loading skeleton for that,
  // which unwatched the checklist; it was thrown away and came back empty, so
  // the card vanished until a fresh read landed.
  testWidgets('the checklist stays on screen while the application reloads', (
    tester,
  ) async {
    tester.view.physicalSize = shortAndroid;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var listReads = 0;
    final slowList = Completer<List<JobApplication>>();
    var checklistReads = 0;
    final slowChecklist = Completer<Checklist>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          applicationRepositoryProvider.overrideWithValue(_FakeRepository()),
          applicationsProvider.overrideWith((ref, status) {
            listReads++;
            return listReads == 1
                ? Future.value([_application])
                : slowList.future;
          }),
          checklistProvider.overrideWith((ref, id) {
            checklistReads++;
            return checklistReads == 1
                ? Future.value(_checklist)
                : slowChecklist.future;
          }),
        ],
        child: MaterialApp(
          theme: buildTackTheme(),
          home: const ApplicationDetailScreen(id: _id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attach the CV you sent'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ApplicationDetailScreen)),
    );
    container
      ..invalidate(applicationsProvider(null))
      ..invalidate(checklistProvider(_id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Attach the CV you sent'), findsOneWidget);
    expect(find.text('Junior data analyst'), findsOneWidget);

    slowList.complete([_application]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Attach the CV you sent'), findsOneWidget);

    slowChecklist.complete(_checklist);
    await tester.pumpAndSettle();
    expect(find.text('Attach the CV you sent'), findsOneWidget);
  });
}
