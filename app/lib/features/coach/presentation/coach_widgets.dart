import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../application/coach.dart';
import 'guide_citations.dart';

/// What is left today, before you type rather than after you run out. Never
/// the whole allowance (R14): a student reads what they have, not a limit.
///
/// It says "AI actions", not "coach questions": the pool is shared with
/// having a CV read properly, a job description analysed and an interview
/// answer read.
class CoachAllowance extends StatelessWidget {
  const CoachAllowance({super.key, required this.allowance});

  final AiAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final line = allowanceLine(allowance);
    return Semantics(
      label: '$line, shared across Tack',
      excludeSemantics: true,
      child: allowance.isSpent ? TackPill(line) : TackPill.teal(line),
    );
  }
}

/// A free question, ready to tap.
class CoachStarter extends StatelessWidget {
  const CoachStarter({super.key, required this.question, required this.onTap});

  final String question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: question,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: TackSpace.cardCompactX,
            vertical: TackSpace.md,
          ),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.listCardAll,
            border: Border.all(color: TackColors.line),
          ),
          child: Row(
            children: [
              Expanded(child: Text(question, style: TackText.rowTitle)),
              TackIcon(
                TackIcons.arrowRight,
                size: 16,
                color: TackColors.maroonText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The starters for this year, as tappable rows.
class CoachStarters extends StatelessWidget {
  const CoachStarters({super.key, required this.mode, required this.onPick});

  final YearMode mode;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final question in startersFor(mode)) ...[
          CoachStarter(question: question, onTap: () => onPick(question)),
          const SizedBox(height: TackSpace.sm),
        ],
      ],
    );
  }
}

/// What a student sees before they have asked anything. Leads with the free
/// questions: a student who does not know which questions cost nothing will
/// spend the day's AI actions finding out.
class CoachOpening extends StatelessWidget {
  const CoachOpening({super.key, required this.mode, required this.onPick});

  final YearMode mode;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ask me about your career', style: TackText.sectionHeader),
        const SizedBox(height: TackSpace.sm),
        Text(
          'I can see your score, your roadmap, your interview practice and '
          'your CV check. The questions below are always free.',
          style: TackText.bodyMuted,
        ),
        const SizedBox(height: TackSpace.xl),
        Text('THESE ARE ALWAYS FREE', style: TackText.monoLabelSmall),
        const SizedBox(height: TackSpace.sm),
        Text(
          'Tack answers these from your own numbers, so they never use an AI '
          'action.',
          style: TackText.meta,
        ),
        const SizedBox(height: TackSpace.md),
        CoachStarters(mode: mode, onPick: onPick),
      ],
    );
  }
}

/// One line of the conversation. A coach reply carries its chips, then the
/// guides it stood on, then whether it cost anything.
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    super.key,
    required this.message,
    required this.onAction,
    required this.onGuide,
  });

  final ChatMessage message;
  final void Function(CoachAction action, String destination) onAction;
  final ValueChanged<String> onGuide;

  @override
  Widget build(BuildContext context) {
    final student = message.isStudent;
    final chips = [
      if (!student)
        for (final action in message.actions)
          if (coachDestination(action) case final destination?)
            TackActionChip(
              action.label,
              onTap: () => onAction(action, destination),
            ),
    ];

    return Align(
      alignment: student ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
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
                border: student ? null : Border.all(color: TackColors.line),
              ),
              child: Text(
                message.body,
                style: TackText.body.copyWith(
                  color: student ? TackColors.onBrand : TackColors.ink,
                ),
              ),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: TackSpace.sm),
              Wrap(
                spacing: TackSpace.sm,
                runSpacing: TackSpace.sm,
                children: chips.take(3).toList(),
              ),
            ],
            if (!student && message.isGrounded) ...[
              const SizedBox(height: TackSpace.sm),
              GuideCitations(guides: message.guides, onOpen: onGuide),
            ],
            // Said on every reply, so a student learns which questions are
            // free without reading documentation.
            if (!student && message.answeredBy != null) ...[
              const SizedBox(height: TackSpace.xs),
              Text(
                message.guideRefusal
                    // Refused before a model was asked, or refunded after.
                    ? "Tack's career guides · nothing used"
                    : message.wasFree
                    ? 'From your own numbers · free'
                    // No number: a caption that names the allowance goes
                    // stale the day the allowance changes.
                    : 'Used one AI action',
                style: TackText.meta,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The wait is real when the model is involved, so this says what is
/// happening rather than spinning silently.
class CoachThinking extends StatelessWidget {
  const CoachThinking(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: TackSpace.xs),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                // A stroke counts as text, so it takes the text shade.
                color: TackColors.maroonText,
              ),
            ),
          ),
          const SizedBox(width: TackSpace.md),
          Expanded(child: Text(text, style: TackText.bodyMuted)),
        ],
      ),
    );
  }
}

/// A question that did not go through: what happened, and the way to send it
/// again as the same question.
class CoachFailedNotice extends StatelessWidget {
  const CoachFailedNotice({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _AmberNotice(
      children: [
        Text(
          message,
          style: TackText.body.copyWith(color: TackColors.amberText),
        ),
        const SizedBox(height: TackSpace.md),
        TackButton.amber('Send again', fullWidth: false, onPressed: onRetry),
      ],
    );
  }
}

/// The day's AI actions are used: the trade, then the free questions, still
/// tappable.
class CoachQuotaNotice extends StatelessWidget {
  const CoachQuotaNotice({
    super.key,
    required this.message,
    required this.mode,
    required this.onPick,
  });

  final String message;
  final YearMode mode;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AmberNotice(
          children: [
            Text(
              message,
              style: TackText.body.copyWith(color: TackColors.amberText),
            ),
          ],
        ),
        const SizedBox(height: TackSpace.md),
        CoachStarters(mode: mode, onPick: onPick),
      ],
    );
  }
}

class _AmberNotice extends StatelessWidget {
  const _AmberNotice({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: TackSpace.cardCompactX,
        vertical: TackSpace.cardCompactY,
      ),
      decoration: BoxDecoration(
        color: TackColors.amberTint,
        borderRadius: BorderRadius.all(TackRadius.listCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class CoachComposer extends StatelessWidget {
  const CoachComposer({
    super.key,
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
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
          excludeSemantics: true,
          onTap: busy ? null : onSend,
          child: GestureDetector(
            onTap: busy ? null : onSend,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: TackMotion.fast,
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: busy ? TackColors.strokeFaint : TackColors.maroon,
                borderRadius: TackRadius.buttonAll,
              ),
              child: Center(
                child: TackIcon(
                  TackIcons.arrowRight,
                  size: 22,
                  color: TackColors.onBrand,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CoachLoading extends StatelessWidget {
  const CoachLoading({super.key});

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
