import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';

import '../application/interview.dart';
import 'interview_widgets.dart';

/// Practising answered questions again, one at a time.
///
/// The student answers out loud first and only then opens their notes, the
/// way a flashcard is turned over. They grade themselves; the database decides
/// when the question comes back.
class ReviewView extends ConsumerStatefulWidget {
  const ReviewView({super.key, required this.questions, required this.onDone});

  final List<DueQuestion> questions;
  final VoidCallback onDone;

  @override
  ConsumerState<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends ConsumerState<ReviewView> {
  int _index = 0;
  bool _revealed = false;
  bool _saving = false;

  DueQuestion get _current => widget.questions[_index];

  Future<void> _grade(ReviewGrade grade) async {
    setState(() => _saving = true);
    try {
      final days = await ref
          .read(interviewRepositoryProvider)
          .review(_current.questionId, grade);
      if (!mounted) return;
      final last = _index == widget.questions.length - 1;
      TackToast.show(
        context,
        message: days == 1 ? 'Back tomorrow.' : 'Back in $days days.',
      );
      if (last) {
        widget.onDone();
        return;
      }
      setState(() {
        _index++;
        _revealed = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _current;
    return TackScaffold(
      header: TackHeader(title: 'Practise again', onBack: widget.onDone),
      pinnedCta: _revealed
          ? Row(
              children: [
                for (final grade in ReviewGrade.values) ...[
                  if (grade != ReviewGrade.again)
                    const SizedBox(width: TackSpace.sm),
                  Expanded(
                    child: grade == ReviewGrade.good
                        ? TackButton(
                            grade.label,
                            onPressed: _saving ? null : () => _grade(grade),
                          )
                        : TackButton.secondary(
                            grade.label,
                            onPressed: _saving ? null : () => _grade(grade),
                          ),
                  ),
                ],
              ],
            )
          : TackButton(
              'Show my notes',
              onPressed: () => setState(() => _revealed = true),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_index + 1} of ${widget.questions.length}'
            '${q.role.isEmpty ? '' : ' · ${q.role}'}',
            style: TackText.meta,
          ),
          const SizedBox(height: TackSpace.md),
          Text(q.question, style: TackText.sectionHeader),
          const SizedBox(height: TackSpace.md),
          Text(
            _revealed
                ? 'How did that go? Pick Again if you got stuck, Easy if it '
                      'came out clearly.'
                : 'Say your answer out loud first. Then open your notes and '
                      'compare.',
            style: TackText.bodyMuted,
          ),
          if (_revealed) ...[
            const SizedBox(height: TackSpace.lg),
            if (!q.hasNotes)
              Text('No notes were saved for this one.', style: TackText.body),
            if (q.answerText?.isNotEmpty ?? false)
              NoteCard(title: 'What you said last time', body: q.answerText!),
            if (q.toImprove.isNotEmpty)
              NoteCard(
                title: 'To work on',
                body: q.toImprove.map((t) => '· $t').join('\n'),
              ),
            if (q.modelAnswer?.isNotEmpty ?? false)
              NoteCard(title: 'A strong answer', body: q.modelAnswer!),
          ],
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }
}
