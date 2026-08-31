import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../data/coach_models.dart';
import '../data/coach_repository.dart';

/// The coach.
///
/// Three questions a day is a hard limit, so the screen's main job — before it
/// is a chat at all — is to make sure a student never spends one by accident.
/// The questions Tack answers for free are offered up front, every reply says
/// which kind it was, and the counter is visible before you type rather than
/// after you have run out.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final _messages = <ChatMessage>[];
  String? _threadId;
  bool _sending = false;
  bool _loaded = false;
  String? _limitNotice;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _adoptHistory((String?, List<ChatMessage>) history) {
    if (_loaded) return;
    _loaded = true;
    _threadId = history.$1;
    _messages.addAll(history.$2);
  }

  Future<void> _send(String question) async {
    final text = question.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _limitNotice = null;
      _messages.add(
        ChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: 'student',
          body: text,
          createdAt: DateTime.now(),
        ),
      );
    });
    _input.clear();
    _toBottom();

    try {
      final reply = await ref
          .read(coachRepositoryProvider)
          .ask(text, threadId: _threadId);
      if (!mounted) return;

      setState(() {
        _threadId = reply.threadId;
        if (reply.hitLimit) {
          _limitNotice = reply.limitMessage;
        } else if (reply.body != null) {
          _messages.add(
            ChatMessage(
              id: 'local-reply-${DateTime.now().microsecondsSinceEpoch}',
              role: 'coach',
              body: reply.body!,
              createdAt: DateTime.now(),
              answeredBy: reply.answeredBy,
            ),
          );
        }
      });
      ref.invalidate(coachRemainingProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _limitNotice = e is Failure
            ? e.message
            : 'The coach could not answer just now. Try again.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
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
    final history = ref.watch(coachHistoryProvider);
    history.whenData(_adoptHistory);
    final remaining = ref.watch(coachRemainingProvider).value;

    return TackScaffold(
      scrollable: false,
      header: TackHeader(
        title: 'Your coach',
        onBack: () => Navigator.of(context).maybePop(),
        trailing: remaining == null ? null : _Allowance(remaining: remaining),
      ),
      // Outside the scroll region, which is what keeps it reachable with a
      // thumb once the keyboard is open.
      pinnedCta: _Composer(
        controller: _input,
        sending: _sending,
        onSend: () => _send(_input.text),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: history.isLoading && _messages.isEmpty
                ? const _Loading()
                : ListView(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    children: [
                      if (_messages.isEmpty)
                        _Opening(onPick: _send)
                      else
                        for (final message in _messages) ...[
                          _Bubble(message: message),
                          const SizedBox(height: TackSpace.stack),
                        ],
                      if (_sending) const _Thinking(),
                      if (_limitNotice case final notice?) ...[
                        const SizedBox(height: TackSpace.sm),
                        _Notice(notice),
                      ],
                      const SizedBox(height: TackSpace.lg),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Three a day, visible before you type rather than after you run out.
class _Allowance extends StatelessWidget {
  const _Allowance({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    final none = remaining == 0;
    return Semantics(
      label: '$remaining of 3 coach questions left today',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: none ? TackColors.sailWhite : TackColors.tealTint,
          borderRadius: TackRadius.pillAll,
        ),
        child: Text(
          '$remaining of 3',
          style: TackText.pill.copyWith(
            color: none ? TackColors.muted : TackColors.tealText,
          ),
        ),
      ),
    );
  }
}

/// What a student sees before they have asked anything.
///
/// Leads with the free questions on purpose. With an allowance of three, a
/// student who does not know which questions cost nothing will spend all three
/// finding out.
class _Opening extends StatelessWidget {
  const _Opening({required this.onPick});

  final void Function(String question) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ask me about your career', style: TackText.sectionHeader),
        const SizedBox(height: TackSpace.sm),
        Text(
          'I can see your score, your skills, your roadmap and what you are '
          'aiming at. Ask anything about getting to your first job.',
          style: TackText.bodyMuted,
        ),
        const SizedBox(height: TackSpace.xl),
        Text('THESE ARE ALWAYS FREE', style: TackText.monoLabelSmall),
        const SizedBox(height: TackSpace.sm),
        Text(
          'Tack answers these from your own numbers, so they never use up your '
          'three questions a day.',
          style: TackText.meta,
        ),
        const SizedBox(height: TackSpace.md),
        for (final question in freeQuestions) ...[
          _Suggestion(question: question, onTap: () => onPick(question)),
          const SizedBox(height: TackSpace.sm),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.question, required this.onTap});

  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.listCardAll,
            border: Border.all(color: TackColors.line),
          ),
          child: Row(
            children: [
              Expanded(child: Text(question, style: TackText.rowTitle)),
              const TackIcon(
                TackIcons.arrowRight,
                size: 16,
                color: TackColors.strokeFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final student = message.isStudent;

    return Align(
      alignment: student ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: student
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: TackSpace.lg,
                vertical: TackSpace.md,
              ),
              decoration: BoxDecoration(
                color: student ? TackColors.maroon : TackColors.white,
                borderRadius: TackRadius.cardAll,
                border: student
                    ? null
                    : Border.all(color: TackColors.line),
              ),
              child: Text(
                message.body,
                style: TackText.body.copyWith(
                  color: student ? TackColors.white : TackColors.ink,
                  fontSize: 15.5,
                ),
              ),
            ),
            // Said on every reply, so a student can learn which questions are
            // free without reading documentation.
            if (!student && message.answeredBy != null) ...[
              const SizedBox(height: 5),
              Text(
                message.wasFree
                    ? 'From your own numbers · free'
                    : 'Used one of your three',
                style: TackText.meta.copyWith(fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The wait is real — eight to fourteen seconds when the model is involved —
/// so this says what is happening rather than spinning silently.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: TackSpace.lg,
          vertical: TackSpace.md,
        ),
        decoration: BoxDecoration(
          color: TackColors.white,
          borderRadius: TackRadius.cardAll,
          border: Border.all(color: TackColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: TackColors.maroon,
              ),
            ),
            const SizedBox(width: TackSpace.md),
            Text('Thinking about your answer', style: TackText.bodyMuted),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.cardCompactX,
        vertical: TackSpace.cardCompactY,
      ),
      decoration: const BoxDecoration(
        color: TackColors.amberTint,
        borderRadius: BorderRadius.all(TackRadius.listCard),
      ),
      child: Text(text, style: TackText.bodyMuted),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TackTextField(
            controller: controller,
            hint: 'Ask about your career',
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: TackSpace.sm),
        Semantics(
          button: true,
          label: 'Send',
          child: GestureDetector(
            onTap: sending ? null : onSend,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: sending ? TackColors.strokeFaint : TackColors.maroon,
                borderRadius: TackRadius.buttonAll,
              ),
              child: const Center(
                child: TackIcon(
                  TackIcons.arrowRight,
                  size: 22,
                  color: TackColors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: const [
      TackSkeleton(height: 22, width: 180),
      SizedBox(height: TackSpace.lg),
      TackSkeleton(height: 56, radius: 18),
      SizedBox(height: TackSpace.stack),
      TackSkeleton(height: 56, radius: 18),
    ],
  );
}
