import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/routing/router.dart';

import '../application/interview.dart';
import 'interview_widgets.dart';
import 'role_picker_sheet.dart';

/// Choosing what to practise: a role from the student's own data, the kind of
/// questions, how hard, and whether to time it.
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
    required InterviewRole role,
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
  /// Null until the student picks one, so the suggestion can arrive first.
  InterviewRole? _picked;
  InterviewType _type = InterviewType.mixed;
  Difficulty _difficulty = Difficulty.medium;

  /// Off by default, on purpose.
  bool _timer = false;

  @override
  Widget build(BuildContext context) {
    final history =
        ref.watch(interviewHistoryProvider).value ?? const <InterviewSession>[];
    final catalogAsync = ref.watch(interviewCatalogProvider);
    final catalog = catalogAsync.value ?? InterviewCatalog.empty;

    // The suggestion is the default until the student chooses for themselves.
    final suggestion = catalog.suggested;
    final suggested = suggestion == null
        ? null
        : catalog.roleBySlug(suggestion.slug) ??
              InterviewRole(slug: suggestion.slug, title: suggestion.title);
    final role = _picked ?? suggested;
    final reason = _picked == null && suggestion != null
        ? reasonLine(suggestion)
        : null;

    return TackScaffold(
      header: TackHeader(
        title: 'Interview practice',
        onBack: () => tackBack(context, fallback: Routes.toolkit),
      ),
      pinnedCta: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stated before the work starts, never after.
          Text(
            'Questions and self-checks are free. Feedback on each answer '
            'uses one AI action.',
            style: TackText.bodyMuted,
          ),
          if (role == null) ...[
            const SizedBox(height: TackSpace.xs),
            Text('Choose a role to start.', style: TackText.meta),
          ],
          const SizedBox(height: TackSpace.sm),
          TackButton(
            'Start practising',
            loading: widget.busy,
            onPressed: role == null
                ? null
                : () => widget.onStart(
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
              onTap: () => widget.onPractiseAgain(due),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Practise again',
                                style: TackText.cardTitle,
                              ),
                            ),
                            const SizedBox(width: TackSpace.sm),
                            TackPill.teal('Free'),
                          ],
                        ),
                        const SizedBox(height: TackSpace.xs),
                        Text(
                          due.length == 1
                              ? 'One answer is ready to try again. It does '
                                    'not use an AI action.'
                              : '${due.length} answers are ready to try '
                                    'again. They do not use AI actions.',
                          style: TackText.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: TackSpace.md),
                  TackIcon(
                    TackIcons.chevronRight,
                    size: 18,
                    color: TackColors.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: TackSpace.xl),
          ],

          if (catalogAsync.hasError && catalogAsync.value == null)
            TackErrorState(
              title: 'Roles did not load',
              body:
                  'Check your connection and try again. The company packs '
                  'below still work.',
              onRetry: () => ref.invalidate(interviewCatalogProvider),
            )
          else
            _RoleCard(
              role: role,
              reason: reason,
              onTap: catalog.isEmpty
                  ? null
                  : () async {
                      final picked = await showRolePicker(context, catalog);
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
          // "behavioural or technical" — it is "I have an interview at a
          // particular company on Thursday". This costs no quota at all: the
          // questions are seeded and the session is written straight to the
          // tables.
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
                    'Practice questions Tack wrote for some well-known '
                    'employers. Free — these do not use one of your daily AI '
                    'actions.',
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
                                  PackDisclaimer(company: pack.name),
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

/// The role being practised, and why it was chosen. Tapping it opens the
/// role picker.
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.reason, this.onTap});

  final InterviewRole? role;
  final String? reason;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = role?.title;
    return Semantics(
      button: true,
      label: title == null
          ? 'Choose a role'
          : 'Practising for $title. Change role',
      onTap: onTap,
      excludeSemantics: true,
      child: TackCard(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: TackSpace.tapTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Practising for', style: TackText.meta),
                    const SizedBox(height: 2),
                    Text(title ?? 'Choose a role', style: TackText.cardTitle),
                    if (reason != null) ...[
                      const SizedBox(height: TackSpace.xs),
                      Text(reason!, style: TackText.bodyMuted),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: TackSpace.md),
              TackIcon(
                TackIcons.chevronRight,
                size: 18,
                color: TackColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
