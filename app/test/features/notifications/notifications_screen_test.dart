import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/notifications/data/notification_repository.dart';
import 'package:tack/features/notifications/presentation/notifications_screen.dart';

import '../../helpers.dart';

const _appId = '7b0c1a52-9a52-4c7e-9a43-3f1f5d3b2a10';

/// Remembers what was marked read. Nothing reaches the network.
class _FakeRepository extends NotificationRepository {
  _FakeRepository()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final read = <String>[];

  @override
  Future<void> markRead(String id) async => read.add(id);
}

final _brief = TackNotification.fromRow({
  'id': 'brief-1',
  'type': 'weekly_brief',
  'title': 'Your week: 2 things',
  'body': 'Send your application before then, or let it go.',
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'payload': {
    'items': [
      {
        'title': 'Meghna Foods closes Wed 28 Oct',
        'why': 'Send your application before then, or let it go.',
        'route': '/applications/$_appId',
      },
      {
        'title': 'One roadmap step is late',
        'why': 'Move a date or tick one off. Nothing is lost.',
        'route': '/roadmap',
      },
    ],
  },
});

Future<_FakeRepository> _pump(WidgetTester tester) async {
  tester.view.physicalSize = shortAndroid;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = _FakeRepository();
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/applications/:id',
        builder: (_, state) =>
            Text('application ${state.pathParameters['id']}'),
      ),
      GoRoute(path: '/roadmap', builder: (_, _) => const Text('roadmap')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) async => [_brief]),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(theme: buildTackTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(loadTackFonts);

  testWidgets('a brief opens as a sheet and an item goes where it points', (
    tester,
  ) async {
    final repository = await _pump(tester);

    await tester.tap(find.text('Your week: 2 things'));
    await tester.pumpAndSettle();

    expect(repository.read, ['brief-1']);
    expect(find.text('One roadmap step is late'), findsOneWidget);

    await tester.tap(find.text('Meghna Foods closes Wed 28 Oct'));
    await tester.pumpAndSettle();

    expect(find.text('application $_appId'), findsOneWidget);
  });

  testWidgets('closing the sheet stays on the updates list', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Your week: 2 things'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('application $_appId'), findsNothing);
  });
}
