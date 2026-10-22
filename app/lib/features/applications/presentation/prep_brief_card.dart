import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/checklist_models.dart';

/// The interview prep brief: what to say and the proof for it, what they may
/// ask, what to ask them, and what to prepare.
///
/// Every talking point is backed by a skill or project the student listed —
/// the worker drops the rest before anything is stored — so the proof line is
/// shown under each one rather than hidden.
class PrepBriefCard extends StatelessWidget {
  const PrepBriefCard({
    super.key,
    required this.brief,
    required this.onRequest,
    this.busy = false,
  });

  final PrepBrief? brief;
  final VoidCallback onRequest;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final brief = this.brief;
    if (brief == null) {
      return TackCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Interview prep', style: TackText.cardTitle),
            const SizedBox(height: TackSpace.sm),
            Text(
              'Talking points backed by your own skills and projects, the '
              'questions they are likely to ask, and questions to ask them. '
              'Uses one AI action.',
              style: TackText.bodyMuted,
            ),
            const SizedBox(height: TackSpace.md),
            TackButton.secondary(
              busy ? 'Writing your brief…' : 'Get your prep brief',
              onPressed: busy ? null : onRequest,
            ),
          ],
        ),
      );
    }

    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Interview prep', style: TackText.cardTitle),
          const SizedBox(height: TackSpace.md),
          _Section(
            title: 'What to say',
            children: [
              for (final p in brief.talkingPoints)
                _Line(p.point, under: 'Proof: ${p.evidence}'),
            ],
          ),
          if (brief.likelyQuestions.isNotEmpty)
            _Section(
              title: 'They may ask',
              children: [
                for (final q in brief.likelyQuestions)
                  _Line(q.question, under: q.why),
              ],
            ),
          if (brief.questionsToAsk.isNotEmpty)
            _Section(
              title: 'Ask them',
              children: [for (final q in brief.questionsToAsk) _Line(q)],
            ),
          if (brief.gaps.isNotEmpty)
            _Section(
              title: 'Prepare for',
              children: [
                for (final g in brief.gaps)
                  _Line(g.skill, under: g.howToPrepare),
              ],
            ),
          const SizedBox(height: TackSpace.sm),
          // Added a skill or a project since? The brief is keyed by what it
          // was built from, so the same profile comes straight back.
          TackButton.ghost(
            busy ? 'Writing your brief…' : 'Refresh brief',
            fullWidth: false,
            onPressed: busy ? null : onRequest,
          ),
          Text(
            'Free if nothing has changed. A changed profile uses one AI action.',
            style: TackText.meta,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: TackSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TackText.monoLabelSmall),
          const SizedBox(height: TackSpace.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.under});

  final String text;
  final String? under;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TackText.body),
          if (under != null) ...[
            const SizedBox(height: 2),
            Text(under!, style: TackText.bodyMuted),
          ],
        ],
      ),
    );
  }
}
