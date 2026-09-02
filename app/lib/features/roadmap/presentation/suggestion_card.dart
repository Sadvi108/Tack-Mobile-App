import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/path_suggestion.dart';

/// Where Tack thinks this student could go, and why it thinks so.
///
/// The reasons are the point. A ranked list with no explanation asks a student
/// to trust a number they cannot check; naming the signal — "your subject
/// leads here", "you said this is what you are aiming at" — turns the same
/// ranking into something they can agree or disagree with. It also keeps the
/// engine honest, because a path that cannot produce a reason is not shown.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onOpen,
  });

  final PathSuggestion suggestion;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final target = suggestion.isTarget;

    return TackCard(
      // The role they told us they wanted gets the emphasis border. It is the
      // one suggestion that is really a confirmation.
      emphasised: target,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (target) ...[
            Text('WHAT YOU SAID YOU WANT', style: TackText.monoLabelSmall),
            const SizedBox(height: TackSpace.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  suggestion.title,
                  style: TackText.cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (suggestion.followed) ...[
                const SizedBox(width: TackSpace.sm),
                TackPill.teal('Following'),
              ],
            ],
          ),
          if (suggestion.summary case final summary?) ...[
            const SizedBox(height: TackSpace.xs),
            Text(
              summary,
              style: TackText.bodyMuted,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: TackSpace.md),
          for (final reason in suggestion.reasons.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: TackIcon(
                      TackIcons.check,
                      size: 13,
                      color: TackColors.tealText,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(width: TackSpace.sm),
                  Expanded(child: Text(reason, style: TackText.meta)),
                ],
              ),
            ),

          const SizedBox(height: TackSpace.md),
          Wrap(
            spacing: TackSpace.sm,
            runSpacing: TackSpace.sm,
            children: [
              if (suggestion.salaryRange case final pay?) _Fact(pay),
              if (suggestion.months case final m?) _Fact('$m months to hireable'),
              if (suggestion.demand case final d?) _Fact('$d demand'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: const BoxDecoration(
        color: TackColors.sailWhite,
        borderRadius: TackRadius.pillAll,
      ),
      child: Text(
        label,
        style: TackText.pill.copyWith(
          color: TackColors.muted,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
