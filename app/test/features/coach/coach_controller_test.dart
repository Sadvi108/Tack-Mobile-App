import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/failure.dart';
import 'package:tack/features/coach/application/coach.dart';
import 'package:tack/features/coach/data/coach_models.dart';
import 'package:tack/features/coach/data/coach_repository.dart';

/// The coach endpoint, scripted one answer at a time.
class _Coach extends Fake implements CoachRepository {
  _Coach(this.answers);

  final List<Object> answers;
  final asked = <(String, String?, String?)>[];

  @override
  Future<CoachReply> ask(
    String question, {
    String? threadId,
    String? operationId,
    void Function(String jobId)? onQueued,
  }) async {
    asked.add((question, operationId, threadId));
    final next = answers.removeAt(0);
    if (next is Failure) throw next;
    if (next is String) {
      onQueued?.call(next);
      return CoachReply(
        threadId: 't1',
        remaining: 9,
        body: 'Thought about.',
        answeredBy: 'model',
      );
    }
    return next as CoachReply;
  }
}

const _reply = CoachReply(
  threadId: 't1',
  remaining: 9,
  body: 'Open your roadmap.',
  answeredBy: 'data',
  intent: 'next',
  actions: [CoachAction(route: 'roadmap', label: 'Open your roadmap')],
);

/// A container whose history provider counts its reads.
(ProviderContainer, int Function()) _container(
  _Coach coach, {
  List<ChatMessage> history = const [],
}) {
  var reads = 0;
  final container = ProviderContainer(
    overrides: [
      coachRepositoryProvider.overrideWithValue(coach),
      coachHistoryProvider.overrideWith((ref) async {
        reads++;
        return (history.isEmpty ? null : 't0', history);
      }),
      aiAllowanceProvider.overrideWith(
        (ref) async => const AiAllowance(used: 1, limit: 10),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Keep the autoDispose controller alive for the test.
  container.listen(coachControllerProvider, (_, _) {});
  return (container, () => reads);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('it adopts the saved conversation once', () async {
    final saved = ChatMessage(
      id: 'm1',
      role: 'student',
      body: 'Earlier question',
      createdAt: DateTime(2026, 11, 1),
    );
    final (container, _) = _container(_Coach([]), history: [saved]);
    await _settle();
    final state = container.read(coachControllerProvider);
    expect(state.restored, isTrue);
    expect(state.threadId, 't0');
    expect(state.messages.single.body, 'Earlier question');
  });

  test(
    'an answer is added with its chips, and history is read again',
    () async {
      final coach = _Coach([_reply]);
      final (container, reads) = _container(coach);
      await _settle();
      final before = reads();

      await container
          .read(coachControllerProvider.notifier)
          .send('What should I do next?');
      await _settle();

      final state = container.read(coachControllerProvider);
      expect(state.phase, isA<CoachIdle>());
      expect(state.threadId, 't1');
      expect(state.messages.map((m) => m.body), [
        'What should I do next?',
        'Open your roadmap.',
      ]);
      expect(state.messages.last.actions.single.route, 'roadmap');
      expect(state.messages.last.intent, 'next');
      expect(reads(), greaterThan(before), reason: 'history was invalidated');
    },
  );

  test('a queued question waits with its job id', () async {
    final coach = _Coach(['job-9']);
    final (container, _) = _container(coach);
    await _settle();
    final phases = <CoachPhase>[];
    container.listen(
      coachControllerProvider.select((s) => s.phase),
      (_, next) => phases.add(next),
    );

    await container.read(coachControllerProvider.notifier).send('How?');

    expect(
      phases.whereType<CoachWaiting>().map((p) => p.jobId),
      contains('job-9'),
    );
    expect(container.read(coachControllerProvider).phase, isA<CoachIdle>());
  });

  test('a spent allowance is the quota state, not a failure', () async {
    final coach = _Coach([const Failure('Used up.', code: 'quota_exhausted')]);
    final (container, _) = _container(coach);
    await _settle();

    await container.read(coachControllerProvider.notifier).send('How?');

    final phase = container.read(coachControllerProvider).phase;
    expect(phase, isA<CoachQuota>());
    expect((phase as CoachQuota).message, coachQuotaMessage);
    expect(coachQuotaMessage, isNot(matches(RegExp(r'\d'))));
  });

  test('a failure can be sent again as the same operation', () async {
    final coach = _Coach([
      const Failure('Something went wrong on our side. Try again.'),
      _reply,
    ]);
    final (container, _) = _container(coach);
    await _settle();
    final notifier = container.read(coachControllerProvider.notifier);

    await notifier.send('How do I network?');
    final failed = container.read(coachControllerProvider).phase;
    expect(failed, isA<CoachFailed>());
    expect(
      (failed as CoachFailed).message,
      'Something went wrong on our side. Try again.',
    );

    await notifier.retry();

    expect(coach.asked.length, 2);
    expect(coach.asked[0].$2, isNotNull);
    expect(coach.asked[1].$2, coach.asked[0].$2);
    final state = container.read(coachControllerProvider);
    expect(
      state.messages.where((m) => m.isStudent).length,
      1,
      reason: 'a retry never adds a second bubble',
    );
    expect(state.phase, isA<CoachIdle>());
  });

  test('two questions never share an operation id', () async {
    final coach = _Coach([_reply, _reply]);
    final (container, _) = _container(coach);
    await _settle();
    final notifier = container.read(coachControllerProvider.notifier);
    await notifier.send('One?');
    await notifier.send('Two?');
    expect(coach.asked[0].$2, isNot(coach.asked[1].$2));
    expect(coach.asked[1].$3, 't1', reason: 'the thread carries on');
  });

  test('offline says the question was not sent, never that it was saved', () {
    final lower = coachOfflineMessage.toLowerCase();
    expect(lower, contains('not sent'));
    expect(lower, isNot(contains('saved')));
    expect(lower, isNot(contains('sync')));
  });

  test('an offline failure shows the offline sentence', () async {
    final coach = _Coach([Failure.offline]);
    final (container, _) = _container(coach);
    await _settle();
    await container.read(coachControllerProvider.notifier).send('How?');
    final phase = container.read(coachControllerProvider).phase;
    expect((phase as CoachFailed).message, coachOfflineMessage);
  });
}
