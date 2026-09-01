import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../data/listing.dart';

/// One opening.
///
/// The fit figure leads, because that is the only thing here a job board
/// cannot tell a student. Everything else — title, company, salary — is on
/// every board in the world; "you already have four of the six skills this
/// asks for, and the two missing are X and Y" is the reason to open Tack
/// instead of Google.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.onOpen,
    this.onSave,
    this.onTrack,
  });

  final Listing listing;

  /// Opens the posting on the board it came from.
  final VoidCallback onOpen;

  /// Null once it is already saved.
  final VoidCallback? onSave;

  /// Set once it is saved: jumps to it in the tracker.
  final VoidCallback? onTrack;

  @override
  Widget build(BuildContext context) {
    final posted = listing.postedRelativeTo(DateTime.now());

    return TackCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: TackText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (listing.company != null) listing.company!,
                        if (listing.isRemote)
                          'Remote'
                        else if (listing.location != null)
                          listing.location!,
                      ].join(' · '),
                      style: TackText.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              _Fit(listing: listing),
            ],
          ),

          if (listing.isScored && listing.asks > 0) ...[
            const SizedBox(height: TackSpace.md),
            TackProgressBar.health(
              value: listing.asks == 0 ? 0 : listing.have / listing.asks,
              height: 6,
            ),
            const SizedBox(height: TackSpace.sm),
            Text(_skillSentence, style: TackText.meta),
          ] else ...[
            const SizedBox(height: TackSpace.md),
            // Not "0% match". The posting did not say what it wants, which is
            // a fact about the posting and not about the student.
            Text(
              'This posting does not list what it asks for, so there is nothing '
              'to match against.',
              style: TackText.meta,
            ),
          ],

          const SizedBox(height: TackSpace.md),
          Row(
            children: [
              if (listing.kindLabel case final kind?) ...[
                _Tag(kind, emphasis: true),
                const SizedBox(width: TackSpace.sm),
              ],
              _Tag(listing.sourceLabel),
              if (posted != null) ...[
                const SizedBox(width: TackSpace.sm),
                _Tag(posted),
              ],
              if (listing.salary != null) ...[
                const SizedBox(width: TackSpace.sm),
                Flexible(child: _Tag(listing.salary!)),
              ],
            ],
          ),

          const SizedBox(height: TackSpace.lg),
          Row(
            children: [
              Expanded(
                child: onSave != null
                    ? TackButton.secondary('Save it', onPressed: onSave)
                    : TackButton.secondary('In your tracker', onPressed: onTrack),
              ),
              const SizedBox(width: TackSpace.sm),
              Expanded(
                child: TackButton.ghost('Open posting', onPressed: onOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _skillSentence {
    final missing = listing.missingSkills;
    if (listing.have == listing.asks) {
      return 'You have everything it asks for.';
    }
    final named = missing.take(2).join(' and ');
    final rest = missing.length > 2 ? ', and ${missing.length - 2} more' : '';
    return listing.have == 0
        ? 'It asks for $named$rest.'
        : '${listing.have} of ${listing.asks} skills. Missing $named$rest.';
  }
}

/// The fit figure, or an honest dash when there is nothing to score.
class _Fit extends StatelessWidget {
  const _Fit({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final fit = listing.fit;
    if (fit == null) {
      return Semantics(
        label: 'Fit unknown',
        excludeSemantics: true,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: TackColors.sailWhite,
            shape: BoxShape.circle,
          ),
          child: Text('–', style: TackText.cardTitle.copyWith(
            color: TackColors.muted,
          )),
        ),
      );
    }

    final (background, foreground) = fit >= 70
        ? (TackColors.tealTint, TackColors.tealText)
        : fit >= 40
        ? (TackColors.amberTint, TackColors.amberText)
        : (TackColors.maroonTint, TackColors.maroon);

    return Semantics(
      label: '$fit percent fit',
      excludeSemantics: true,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Text(
          '$fit',
          style: TackText.cardTitle.copyWith(color: foreground, fontSize: 15),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.emphasis = false});

  final String label;

  /// The kind of work leads the row, because it is the thing a student is
  /// filtering on.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis ? TackColors.tealTint : TackColors.sailWhite,
        borderRadius: TackRadius.pillAll,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TackText.pill.copyWith(
          color: emphasis ? TackColors.tealText : TackColors.muted,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
