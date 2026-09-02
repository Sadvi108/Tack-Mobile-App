import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/dashboard_feed.dart';
import 'motion.dart';

/// What the student is aiming at, and how far off it they are.
///
/// Three states, because there are genuinely three:
///
///   * a target they chose        -> how close they are, and the gap
///   * a path they only follow    -> an offer to make it the target
///   * neither, but a role typed
///     during onboarding          -> an offer to pick the matching path
///
/// The middle one exists because the dashboard used to collapse it into the
/// first: following Content writer while browsing was rendered as "YOUR
/// TARGET: Content writer" over a profile whose target role said Backend
/// developer. Following is not choosing, and the card now says which it is.

/// How close the student is to the job they picked, and what is between them.
///
/// The gap is named rather than counted. "Four skills missing" is a score;
/// "SQL, Excel and Power BI" is a plan, and the second is the only one a
/// student can act on this afternoon.
///
/// Core skills lead, and they are the only ones shown. A nice-to-have listed
/// beside a core requirement tells a student the two are equally urgent, which
/// is the most expensive thing this card could get wrong.
class PathFitCard extends StatelessWidget {
  const PathFitCard({
    super.key,
    required this.pathTitle,
    required this.gap,
    required this.held,
    required this.asked,
    required this.onOpen,
  });

  final String pathTitle;
  final List<SkillGap> gap;
  final int held;
  final int asked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final core = gap.where((s) => s.isCore).toList();
    final shown = (core.isEmpty ? gap : core).take(4).toList();
    final fraction = asked == 0 ? 0.0 : held / asked;

    return TackCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR TARGET', style: TackText.monoLabelSmall),
          const SizedBox(height: TackSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  pathTitle,
                  style: TackText.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              if (asked > 0)
                TackCountUp(
                  (fraction * 100).round(),
                  suffix: '%',
                  style: TackText.cardTitle.copyWith(
                    color: TackColors.maroonText,
                  ),
                  semanticsLabel:
                      'You have $held of the $asked skills this path asks for',
                ),
            ],
          ),
          const SizedBox(height: TackSpace.md),
          TackProgressBar(value: fraction, height: 8),
          const SizedBox(height: TackSpace.sm),
          Text(
            asked == 0
                ? 'Skills for this path are still being set up.'
                : 'You have $held of the $asked skills it asks for.',
            style: TackText.meta,
          ),
          if (shown.isNotEmpty) ...[
            const SizedBox(height: TackSpace.lg),
            Text(
              core.isEmpty ? 'Still to pick up' : 'Core skills still to go',
              style: TackText.fieldLabel,
            ),
            const SizedBox(height: TackSpace.sm),
            Wrap(
              spacing: TackSpace.sm,
              runSpacing: TackSpace.sm,
              children: [
                for (var i = 0; i < shown.length; i++)
                  TackReveal(index: i, offset: 6, child: _SkillChip(shown[i])),
                if (gap.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${gap.length - shown.length} more',
                      style: TackText.meta,
                    ),
                  ),
              ],
            ),
          ] else if (asked > 0) ...[
            const SizedBox(height: TackSpace.md),
            Text(
              'Every skill this path asks for is already on your profile.',
              style: TackText.bodyMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip(this.skill);

  final SkillGap skill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: skill.isCore ? TackColors.maroonTint : TackColors.sailWhite,
        borderRadius: TackRadius.pillAll,
      ),
      child: Text(
        skill.name,
        style: TackText.chip.copyWith(
          fontSize: 14,
          color: skill.isCore ? TackColors.maroonText : TackColors.ink,
        ),
      ),
    );
  }
}

/// Shown when the student has no target yet.
///
/// It leads with their own words. `profiles.target_role` is what they typed
/// during onboarding — "Backend developer" — and it is the strongest signal
/// Tack has about where they want to end up. The dashboard used to ignore it
/// entirely in favour of whatever path they had last tapped Follow on, which
/// is how somebody aiming at backend work ended up looking at a content
/// writing target on their home screen.
class NoTargetCard extends StatelessWidget {
  const NoTargetCard({
    super.key,
    required this.onBrowse,
    this.following,
    this.statedRole,
    this.onOpen,
    this.onChoose,
  });

  /// A path they follow but have not committed to.
  final FollowedPath? following;

  /// The role they named during onboarding, if they named one.
  final String? statedRole;

  final VoidCallback onBrowse;

  /// Opens the path so they can read it before committing.
  final VoidCallback? onOpen;

  /// Commits: makes this the target. Separate from [onOpen] because the card
  /// should not make the decision for them just because they tapped it.
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final followed = following;
    final role = statedRole?.trim();
    final hasRole = role != null && role.isNotEmpty;

    // Worth pointing out only when the two genuinely differ. Comparing
    // loosely, so "Backend Developer" and "backend developer" are one answer.
    final mismatched =
        followed != null &&
        hasRole &&
        followed.title.toLowerCase().trim() != role.toLowerCase();

    return TackCard(
      onTap: followed == null ? onBrowse : onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            followed == null ? 'NO TARGET YET' : 'NOT YOUR TARGET YET',
            style: TackText.monoLabelSmall,
          ),
          const SizedBox(height: TackSpace.sm),
          Text(_title(followed, role, hasRole), style: TackText.cardTitle),
          const SizedBox(height: TackSpace.sm),
          Text(
            _body(followed, role, hasRole, mismatched),
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.lg),
          if (followed != null && onChoose != null) ...[
            TackButton.secondary('Make it my target', onPressed: onChoose),
            const SizedBox(height: TackSpace.sm),
            TackButton.ghost('Look at it first', onPressed: onOpen),
          ] else
            TackButton.secondary('Find my path', onPressed: onBrowse),
        ],
      ),
    );
  }

  static String _title(FollowedPath? followed, String? role, bool hasRole) {
    if (followed != null) return 'You are following ${followed.title}';
    if (hasRole) return 'You said you want to be a $role';
    return 'Pick something to aim at';
  }

  static String _body(
    FollowedPath? followed,
    String? role,
    bool hasRole,
    bool mismatched,
  ) {
    if (followed != null) {
      return mismatched
          ? 'You told us you are aiming at $role. Make one of them your target '
                'and Tack will build the roadmap and the skill list around it.'
          : 'Make it your target and Tack will build your roadmap and skill '
                'list around it.';
    }
    if (hasRole) {
      return 'Pick the career path that matches and Tack turns it into a '
          'roadmap, a skill list and a score that means something.';
    }
    return 'Your roadmap, the skills worth learning and what your score is '
        'measured against all build from it.';
  }
}
