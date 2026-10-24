import 'package:flutter/material.dart';

import '../../../design/tack.dart';
import '../data/first_read_models.dart';

/// How three readers got on with the CV: where their interest rose and fell,
/// where each one stopped, what stuck, and the one change each would ask for.
///
/// Borrowed from First Reader (awesome-llm-apps, agent_skills/first-reader):
/// the quit point is the sharpest thing a review can say, so it leads.
class FirstReadCard extends StatelessWidget {
  const FirstReadCard({
    super.key,
    required this.read,
    required this.onRequest,
    this.busy = false,
  });

  final FirstRead? read;
  final VoidCallback onRequest;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final read = this.read;
    if (read == null) {
      return TackCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How a recruiter reads this', style: TackText.cardTitle),
            const SizedBox(height: TackSpace.sm),
            Text(
              'Three readers — a recruiter with eight seconds, a hiring '
              'manager and an HR officer — read your CV in order. See where '
              'each one stops, what they remember, and the one change each '
              'would ask for. Uses one AI action.',
              style: TackText.bodyMuted,
            ),
            const SizedBox(height: TackSpace.md),
            TackButton.secondary(
              busy ? 'Reading your CV…' : 'Get a first read',
              onPressed: busy ? null : onRequest,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How a recruiter reads this', style: TackText.sectionHeader),
        for (final reader in read.readers) ...[
          const SizedBox(height: TackSpace.md),
          _ReaderCard(read: read, reader: reader),
        ],
      ],
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({required this.read, required this.reader});

  final FirstRead read;
  final ReaderVerdict reader;

  @override
  Widget build(BuildContext context) {
    final stopped = read.stoppedAt(reader);
    return TackCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reader.name, style: TackText.cardTitle),
          const SizedBox(height: TackSpace.xs),
          Text(
            stopped == null ? 'Read to the end' : 'Stopped at $stopped',
            style: TackText.rowTitle.copyWith(
              color: stopped == null
                  ? TackColors.tealText
                  : TackColors.maroonText,
            ),
          ),
          const SizedBox(height: TackSpace.md),
          _InterestStrip(read: read, reader: reader),
          const SizedBox(height: TackSpace.md),
          Text('“${reader.sayback}”', style: TackText.body),
          if (reader.remembered.isNotEmpty) ...[
            const SizedBox(height: TackSpace.sm),
            Text(
              'Remembered: ${reader.remembered.map((r) => '“$r”').join(', ')}',
              style: TackText.bodyMuted,
            ),
          ],
          const SizedBox(height: TackSpace.sm),
          Text('Change: ${reader.oneAction}', style: TackText.body),
        ],
      ),
    );
  }
}

/// One mark per section the reader reached: taller for interest, shorter for
/// fading, and none past where they stopped.
class _InterestStrip extends StatelessWidget {
  const _InterestStrip({required this.read, required this.reader});

  final FirstRead read;
  final ReaderVerdict reader;

  @override
  Widget build(BuildContext context) {
    final reached = reader.quitChunk == 0
        ? read.chunks
        : read.chunks.where((c) => c.index <= reader.quitChunk).toList();
    final label = reached
        .map((c) => '${c.section} ${_word(reader.interest(c.index))}')
        .join(', ');

    return Semantics(
      label: 'Interest by section: $label',
      excludeSemantics: true,
      child: SizedBox(
        height: 28,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final c in read.chunks) ...[
              Expanded(
                child: c.index > reader.quitChunk && reader.quitChunk != 0
                    ? const SizedBox.shrink()
                    : Container(
                        height: 6.0 + 5.0 * (reader.interest(c.index) + 2),
                        decoration: BoxDecoration(
                          color: reader.interest(c.index) > 0
                              ? TackColors.tealText
                              : reader.interest(c.index) < 0
                              ? TackColors.maroonText
                              : TackColors.muted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
              if (c != read.chunks.last) const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    );
  }

  static String _word(int v) => switch (v) {
    2 => 'very interested',
    1 => 'interested',
    -1 => 'fading',
    -2 => 'about to stop',
    _ => 'neutral',
  };
}
