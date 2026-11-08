import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/coach.dart';
import 'coach_widgets.dart';

/// The coach.
///
/// The daily AI allowance is small and shared with the rest of Tack, so the
/// screen's main job — before it is a chat at all — is to make sure a student
/// never spends an action by accident. The free questions for their year are
/// offered up front, every reply says which kind it was, what is left today
/// is visible before they type, and every reply points at a screen to open.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String question) {
    if (question.trim().isEmpty) return;
    if (ref.read(coachControllerProvider).busy) return;
    _input.clear();
    ref.read(coachControllerProvider.notifier).send(question);
  }

  void _open(CoachAction action, String destination, YearMode mode) {
    ref.read(coachControllerProvider.notifier).recordTap(action, mode);
    tackOpen(context, destination);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: TackMotion.normal,
        curve: TackMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final coach = ref.watch(coachControllerProvider);
    final mode = ref.watch(modeProvider);
    final allowance = ref.watch(aiAllowanceProvider).value;
    ref.listen(
      coachControllerProvider.select(
        (s) => (s.messages.length, s.phase.runtimeType),
      ),
      (_, _) => _toBottom(),
    );

    final phase = coach.phase;
    return TackScaffold(
      scrollable: false,
      header: TackHeader(
        title: 'Your coach',
        onBack: () => tackBack(context, fallback: Routes.toolkit),
      ),
      // Outside the scroll region, which is what keeps it reachable with a
      // thumb once the keyboard is open. It stays enabled when the day's AI
      // actions are used: the free questions still work.
      pinnedCta: CoachComposer(
        controller: _input,
        busy: coach.busy,
        onSend: () => _send(_input.text),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allowance != null) ...[
            CoachAllowance(allowance: allowance),
            const SizedBox(height: TackSpace.md),
          ],
          Expanded(
            child: coach.loading && coach.messages.isEmpty
                ? const CoachLoading()
                : ListView(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    children: [
                      if (coach.messages.isEmpty)
                        CoachOpening(mode: mode, onPick: _send)
                      else
                        for (final message in coach.messages) ...[
                          CoachBubble(
                            message: message,
                            onAction: (action, destination) =>
                                _open(action, destination, mode),
                            onGuide: (slug) =>
                                tackOpen(context, Routes.path(slug)),
                          ),
                          const SizedBox(height: TackSpace.stack),
                        ],
                      ...switch (phase) {
                        CoachSending() => [
                          const CoachThinking('Looking at your numbers'),
                        ],
                        CoachWaiting() => [
                          const CoachThinking(
                            'Thinking about your answer. You can leave this '
                            'screen. The answer is saved here.',
                          ),
                        ],
                        CoachFailed(:final message) => [
                          CoachFailedNotice(
                            message: message,
                            onRetry: () => ref
                                .read(coachControllerProvider.notifier)
                                .retry(),
                          ),
                        ],
                        CoachQuota(:final message) => [
                          CoachQuotaNotice(
                            message: message,
                            mode: mode,
                            onPick: _send,
                          ),
                        ],
                        CoachIdle() => const <Widget>[],
                      },
                      const SizedBox(height: TackSpace.lg),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
