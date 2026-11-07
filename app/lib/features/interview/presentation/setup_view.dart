import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

import '../application/interview.dart';

class InterviewSetupView extends ConsumerStatefulWidget {
  const InterviewSetupView({
    super.key,
    required this.busy,
    required this.onStart,
    required this.onStartPack,
    required this.onPractiseAgain,
  });

  final void Function(List<DueQuestion> due) onPractiseAgain;

  final bool busy;
  final void Function({
    required String role,
    required InterviewType type,
    required Difficulty difficulty,
    required bool timer,
  })
  onStart;

  final void Function(CompanyPack pack, bool timer) onStartPack;

  @override
  ConsumerState<InterviewSetupView> createState() => _InterviewSetupViewState();
}

class _InterviewSetupViewState extends ConsumerState<InterviewSetupView> {
  /// Null until the student picks one, so the default can follow their target
  /// role once the profile resolves.
  ///
  /// This was a `late` field initialised from `ref.read` on first build, which
  /// meant that if the profile had not loaded yet — the ordinary case, it is a
  /// FutureProvider — every student was offered "Frontend developer" whatever
  /// they were actually aiming at.
  String? _picked;
  InterviewType _type = InterviewType.mixed;
  Difficulty _difficulty = Difficulty.medium;

  /// Off by default, on purpose.
  bool _timer = false;

  static const _roles = [
    'Frontend developer',
    'Backend developer',
    'Data analyst',
    'Digital marketer',
    'HR executive',
    'Business analyst',
    'Graphic designer',
    'QA engineer',
    'Accountant',
    'Content writer',
  ];

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(interviewHistoryProvider).value ?? const <InterviewSession>[];
    final role =
        _picked ??
        ref.watch(profileProvider).value?.targetRole ??
        'Frontend developer';

    return TackScaffold(
      header: TackHeader(
        title: 'Interview practice',
        onBack: () => tackBack(context),
      ),
      pinnedCta: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stated before the work starts, never after. Questions a role has
          // already been given come from the bank and cost nothing; new ones
          // and every piece of feedback are model calls.
          Text(
            'Feedback on each answer uses one AI action. New questions for a '
            'role can use one too.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.sm),
          TackButton(
            'Start practising',
            loading: widget.busy,
            onPressed: () => widget.onStart(
              role: role,
              type: _type,
              difficulty: _difficulty,
              timer: _timer,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Free, like the company packs: no model, no daily AI action.
          if (ref.watch(dueQuestionsProvider).value case final due?
              when due.isNotEmpty) ...[
            TackCard(
              background: TackColors.tealTint,
              onTap: () => widget.onPractiseAgain(due),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Practise again', style: TackText.cardTitle),
                        const SizedBox(height: TackSpace.xs),
                        Text(
                          due.length == 1
                              ? 'One answer is ready to practise again. '
                                    'Free — it does not use an AI action.'
                              : '${due.length} answers are ready to practise '
                                    'again. Free — they do not use AI actions.',
                          style: TackText.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: TackSpace.md),
                  TackIcon(
                    TackIcons.chevronRight,
                    size: 18,
                    color: TackColors.tealText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: TackSpace.xl),
          ],
          Text('Which role?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          TackSelectField<String>(
            hint: 'Choose a role',
            value: role,
            valueLabel: (r) => r,
            onTap: () async {
              final picked = await showTackSheet<String>(
                context: context,
                title: 'Practise for',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final role in _roles)
                      TackTapRow(
                        onTap: () => Navigator.of(context).pop(role),
                        padding: const EdgeInsets.symmetric(
                          horizontal: TackSpace.screen,
                          vertical: 14,
                        ),
                        child: Text(role, style: TackText.rowTitle),
                      ),
                    const SizedBox(height: TackSpace.lg),
                  ],
                ),
              );
              if (picked != null) setState(() => _picked = picked);
            },
          ),
          const SizedBox(height: TackSpace.lg),

          Text('What kind of questions?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final type in InterviewType.values)
                TackChip(
                  type.label,
                  selected: _type == type,
                  onTap: () => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.lg),

          Text('How hard?', style: TackText.fieldLabel),
          const SizedBox(height: TackSpace.sm),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              for (final difficulty in Difficulty.values)
                TackChip(
                  difficulty.label,
                  selected: _difficulty == difficulty,
                  onTap: () => setState(() => _difficulty = difficulty),
                ),
            ],
          ),
          const SizedBox(height: TackSpace.lg),

          TackCard(
            compact: true,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Timed answers', style: TackText.rowTitle),
                      const SizedBox(height: 2),
                      Text(
                        'Off by default. Turn it on when you already feel ready.',
                        style: TackText.meta,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _timer,
                  activeThumbColor: TackColors.maroon,
                  onChanged: (v) => setState(() => _timer = v),
                ),
              ],
            ),
          ),

          // The question a student actually has the night before is not
          // "behavioural or technical" — it is "I have an interview at bKash
          // on Thursday". This costs no quota at all: the questions are seeded
          // and the session is written straight to the tables.
          Consumer(
            builder: (context, ref, _) {
              final packs = ref.watch(companyPacksProvider).value ?? const [];
              if (packs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: TackSpace.xl),
                  Text(
                    'Interviewing somewhere specific?',
                    style: TackText.sectionHeader,
                  ),
                  const SizedBox(height: TackSpace.xs),
                  Text(
                    'What each is known to ask. Free — these do not use one of '
                    'your daily AI actions.',
                    style: TackText.bodyMuted,
                  ),
                  const SizedBox(height: TackSpace.md),
                  for (final pack in packs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: TackSpace.row),
                      child: TackCard(
                        compact: true,
                        onTap: () => widget.onStartPack(pack, _timer),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pack.name, style: TackText.rowTitle),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${pack.questions.length} questions',
                                    style: TackText.meta,
                                  ),
                                ],
                              ),
                            ),
                            TackIcon(
                              TackIcons.chevronRight,
                              size: 18,
                              color: TackColors.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          if (history.isNotEmpty) ...[
            const SizedBox(height: TackSpace.xl),
            Text('Before', style: TackText.sectionHeader),
            const SizedBox(height: TackSpace.md),
            for (final past in history.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: TackSpace.row),
                child: TackCard(
                  compact: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(past.role, style: TackText.rowTitle),
                            const SizedBox(height: 2),
                            Text(
                              '${past.answeredCount} questions',
                              style: TackText.meta,
                            ),
                          ],
                        ),
                      ),
                      if (past.overallScore != null)
                        TackPill.teal(
                          '${past.overallScore!.toStringAsFixed(1)}/10',
                        ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}
