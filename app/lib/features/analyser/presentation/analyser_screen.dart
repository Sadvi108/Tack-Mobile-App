import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/analyser_controller.dart';
import '../data/analysis_models.dart';
import '../data/analysis_repository.dart';

/// The job description analyser.
///
/// The quota is stated before the work starts, not after, so nobody burns a
/// run by accident. The result leads with the match percentage, then splits
/// skills into what the student has and what they do not.
class AnalyserScreen extends ConsumerStatefulWidget {
  const AnalyserScreen({super.key});

  @override
  ConsumerState<AnalyserScreen> createState() => _AnalyserScreenState();
}

class _AnalyserScreenState extends ConsumerState<AnalyserScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyserControllerProvider);
    final remaining = ref.watch(analysisQuotaProvider).value;

    return TackScaffold(
      header: TackHeader(
        title: 'Job analyser',
        onBack: () => context.pop(),
        trailing: state is AnalysisReady
            ? TackButton.ghost(
                'New',
                fullWidth: false,
                onPressed: () {
                  _text.clear();
                  ref.read(analyserControllerProvider.notifier).reset();
                },
              )
            : null,
      ),
      pinnedCta: switch (state) {
        AnalysisIdle() => TackButton(
          'Analyse it',
          onPressed: (remaining ?? 0) > 0 && _text.text.trim().length >= 80
              ? () => ref
                    .read(analyserControllerProvider.notifier)
                    .analyse(_text.text)
              : null,
        ),
        AnalysisReady(match: final match) when match.missing.isNotEmpty =>
          TackButton(
            'Add missing skills to my roadmap',
            onPressed: () => _addToRoadmap(match),
          ),
        _ => null,
      },
      body: switch (state) {
        AnalysisIdle() => _Input(
          controller: _text,
          remaining: remaining,
          onChanged: () => setState(() {}),
        ),
        AnalysisQueued() => const _Processing(),
        AnalysisFailed(
          message: final message,
          quotaExhausted: final exhausted,
        ) =>
          exhausted
              ? TackQuotaState(
                  resetsAt: 'midnight',
                  onGoToRoadmap: () => context.go(Routes.roadmap),
                )
              : TackErrorState(
                  body: message,
                  onRetry: () =>
                      ref.read(analyserControllerProvider.notifier).reset(),
                ),
        AnalysisReady(
          analysis: final analysis,
          match: final match,
          cached: final cached,
        ) =>
          _Result(analysis: analysis, match: match, cached: cached),
      },
    );
  }

  Future<void> _addToRoadmap(JdMatch match) async {
    try {
      final added = await ref
          .read(analysisRepositoryProvider)
          .addMissingSkillsToRoadmap(match.missing);
      if (!mounted) return;
      TackToast.show(
        context,
        message: added == 0
            ? 'Nothing new to add.'
            : 'Added $added ${added == 1 ? 'skill' : 'skills'} to your roadmap.',
        actionLabel: 'Open',
        onAction: () => context.go(Routes.roadmap),
      );
    } catch (e) {
      if (!mounted) return;
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    required this.remaining,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int? remaining;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final left = remaining ?? AnalysisRepository.dailyQuota;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stated before the work starts, never after.
        TackCard(
          background: left > 0 ? TackColors.tealTint : TackColors.amberTint,
          compact: true,
          child: Row(
            children: [
              TackIcon(
                TackIcons.info,
                size: 20,
                color: left > 0 ? TackColors.tealText : TackColors.amberText,
              ),
              const SizedBox(width: TackSpace.md),
              Expanded(
                child: Text(
                  left > 0
                      ? '$left of ${AnalysisRepository.dailyQuota} analyses left today. '
                            'They reset at midnight.'
                      : 'No analyses left today. They reset at midnight.',
                  style: TackText.bodyMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: TackSpace.stackLoose),
        Text('Paste the job description', style: TackText.sectionHeader),
        const SizedBox(height: TackSpace.sm),
        Text(
          'The whole thing, including the requirements. Analysis takes about a minute '
          'and you can close the app while it runs.',
          style: TackText.bodyMuted,
        ),
        const SizedBox(height: TackSpace.md),
        TackTextField(
          hint: 'Paste here…',
          controller: controller,
          maxLines: 12,
          minLines: 8,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: TackSpace.sm),
        Text(
          controller.text.trim().length < 80
              ? 'Paste a bit more — a line or two is not enough to analyse.'
              : '${controller.text.trim().length} characters',
          style: TackText.meta.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: TackSpace.xl),
      ],
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reading the description', style: TackText.cardTitle),
              const SizedBox(height: TackSpace.md),
              LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: TackColors.line,
                color: TackColors.teal,
              ),
              const SizedBox(height: TackSpace.md),
              Text(
                'This takes about a minute. You can close the app — we will have the '
                'result waiting.',
                style: TackText.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.analysis,
    required this.match,
    required this.cached,
  });

  final JdAnalysis analysis;
  final JdMatch match;
  final bool cached;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackCard(
          background: TackColors.maroon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                analysis.jobTitle,
                style: TackText.bodyMuted.copyWith(
                  color: const Color(0xD1FFFFFF),
                ),
              ),
              const SizedBox(height: TackSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${match.matchPercent}%',
                    style: TackText.heroNumber.copyWith(
                      color: TackColors.onBrand,
                    ),
                  ),
                  const SizedBox(width: TackSpace.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'match',
                      style: TackText.cardTitle.copyWith(
                        color: const Color(0xD1FFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TackSpace.sm),
              Text(
                match.missing.isEmpty
                    ? 'You have everything this role asks for.'
                    : 'You have ${match.matched.length} of '
                          '${match.matched.length + match.missing.length} skills it asks for.',
                style: TackText.bodyMuted.copyWith(
                  color: const Color(0xD1FFFFFF),
                ),
              ),
            ],
          ),
        ),
        if (cached) ...[
          const SizedBox(height: TackSpace.sm),
          Text(
            'This description had already been analysed, so it cost you nothing.',
            style: TackText.meta.copyWith(fontSize: 13.5),
          ),
        ],
        const SizedBox(height: TackSpace.stackLoose),

        if (match.matched.isNotEmpty) ...[
          Text('What you already have', style: TackText.sectionHeader),
          const SizedBox(height: TackSpace.md),
          _ChipCard(items: match.matched, teal: true),
          const SizedBox(height: TackSpace.stackLoose),
        ],

        if (match.missing.isNotEmpty) ...[
          Text('What is missing', style: TackText.sectionHeader),
          const SizedBox(height: TackSpace.md),
          _ChipCard(items: match.missing, teal: false),
          const SizedBox(height: TackSpace.stackLoose),
        ],

        _ListCard(
          title: 'Qualifications it asks for',
          items: analysis.qualifications,
        ),
        _ListCard(
          title: 'What you would be doing',
          items: analysis.responsibilities,
        ),
        if (analysis.experience != null)
          _ListCard(title: 'Experience', items: [analysis.experience!]),

        const SizedBox(height: TackSpace.xl),
      ],
    );
  }
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.items, required this.teal});

  final List<String> items;
  final bool teal;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      compact: true,
      child: Wrap(
        spacing: TackSpace.sm,
        runSpacing: TackSpace.sm,
        children: [
          for (final item in items)
            teal ? TackPill.teal(item) : TackPill.amber(item),
        ],
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.stackLoose),
      child: TackCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TackText.cardTitle),
            const SizedBox(height: TackSpace.md),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: TackSpace.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 9, right: 10),
                      decoration: BoxDecoration(
                        color: TackColors.maroon,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Text(item, style: TackText.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
