import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/vault/application/cv_check.dart';
import 'package:tack/features/vault/presentation/cv_check_entry_screen.dart';
import 'package:tack/features/vault/presentation/cv_check_screen.dart';
import 'package:tack/routing/router.dart';

import '../../helpers.dart';

TackDocument _cv(
  String id,
  String mime, {
  bool isDefault = false,
  int day = 1,
}) => TackDocument(
  id: id,
  type: DocumentType.cv,
  title: id,
  storagePath: 'users/u/$id',
  status: DocumentStatus.ready,
  mimeType: mime,
  isDefault: isDefault,
  createdAt: DateTime(2026, 11, day),
);

const _pdf = 'application/pdf';
const _docx =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// The check is "Free CV check" opened without naming a CV: from the Toolkit,
/// from Home, from the coach. It picks the CV itself, or says what to do when
/// there is none it can read.
void main() {
  setUpAll(loadTackFonts);

  Future<GoRouter> pump(
    WidgetTester tester,
    Future<List<TackDocument>> Function() documents,
  ) async {
    tester.view.physicalSize = shortAndroid;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: Routes.cvCheck,
      routes: [
        GoRoute(
          path: Routes.cvCheck,
          builder: (_, _) => const CvCheckEntryScreen(),
        ),
        GoRoute(
          path: Routes.vault,
          builder: (_, _) => const Scaffold(body: Text('documents page')),
        ),
        GoRoute(
          path: Routes.cvBuilder,
          builder: (_, _) => const Scaffold(body: Text('builder page')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsProvider.overrideWith((ref) => documents()),
          // The check itself stays loading: this test is about which CV.
          cvCheckProvider.overrideWith(
            (ref, id) => Completer<Map<String, dynamic>>().future,
          ),
        ],
        child: MaterialApp.router(
          theme: buildTackTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return router;
  }

  String? checkedId(WidgetTester tester) {
    final screens = tester.widgetList<CvCheckScreen>(
      find.byType(CvCheckScreen),
    );
    return screens.isEmpty ? null : screens.single.documentId;
  }

  testWidgets('opens the check for the default CV it can read', (tester) async {
    await pump(
      tester,
      () async => [
        _cv('newest', _pdf, day: 9),
        _cv('default', _docx, isDefault: true, day: 2),
      ],
    );
    expect(checkedId(tester), 'default');
    expect(hasOverflow(tester), isFalse);
  });

  testWidgets('a default it cannot read falls back to the newest it can', (
    tester,
  ) async {
    await pump(
      tester,
      () async => [
        _cv('photo', 'image/jpeg', isDefault: true, day: 9),
        _cv('older', _pdf, day: 1),
        _cv('newer', _pdf, day: 5),
      ],
    );
    expect(checkedId(tester), 'newer');
  });

  testWidgets('no CV says to add one, and offers both ways', (tester) async {
    final router = await pump(tester, () async => const []);
    expect(checkedId(tester), isNull);
    expect(find.text('Add your CV to check it'), findsOneWidget);
    expect(
      find.text(
        'Upload a PDF or Word file, or build one from your profile. The check '
        'is free.',
      ),
      findsOneWidget,
    );
    expect(find.text('Build my CV'), findsOneWidget);
    expect(hasOverflow(tester), isFalse);

    await tester.tap(find.text('Add my CV'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.vault);
  });

  testWidgets('only a photo of a CV asks for a PDF or Word file', (
    tester,
  ) async {
    await pump(tester, () async => [_cv('photo', 'image/jpeg')]);
    expect(checkedId(tester), isNull);
    expect(find.text('Add your CV as a PDF or Word file'), findsOneWidget);
    expect(
      find.text(
        'The free check reads PDF and Word files. Upload one of those, or '
        'build one from your profile.',
      ),
      findsOneWidget,
    );
    expect(find.text('Add my CV'), findsOneWidget);
    expect(find.text('Build my CV'), findsOneWidget);
  });

  testWidgets('documents that did not load can be tried again', (tester) async {
    var calls = 0;
    await pump(tester, () async {
      calls++;
      throw Exception('offline');
    });
    await tester.pumpAndSettle();
    expect(find.text('Your documents did not load'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);

    final before = calls;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(before));
  });
}
