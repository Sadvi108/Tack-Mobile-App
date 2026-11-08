import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/ai/allowance.dart';
import 'package:tack/features/toolkit/application/toolkit_copy.dart';
import 'package:tack/features/toolkit/application/toolkit_status.dart';
import 'package:tack/features/toolkit/application/toolkit_tools.dart';

/// Every status the hub can be in, including the ones still loading.
final _statuses = [
  for (final documents in [null, 0, 1, 4])
    for (final cvs in [null, 0, 1, 2, 3])
      if (documents == null || cvs == null || cvs <= documents)
        for (final checkable in [null, false, true])
          for (final due in [null, 0, 1, 3])
            ToolkitStatus(
              documentCount: documents,
              cvCount: cvs,
              hasCheckableCv: checkable,
              dueCount: due,
            ),
];

/// Every string the hub can show in [mode].
List<String> _strings(YearMode mode) => [
  toolkitTitle,
  toolkitSubtitle(mode),
  for (final section in ToolkitSection.values) sectionTitle(section, mode),
  for (final status in _statuses)
    for (final tool in ToolkitTool.values) ...[
      toolTitle(tool, mode, status),
      toolBody(tool, mode, status),
    ],
  documentsErrorTitle,
  documentsErrorBody,
  for (final used in [0, 1, 3, 4])
    allowanceNote(AiAllowance(used: used, limit: 4)),
];

/// Titles are single phrases, so sentence case is checkable word by word.
List<String> _titles(YearMode mode) => [
  toolkitTitle,
  for (final section in ToolkitSection.values) sectionTitle(section, mode),
  for (final status in _statuses)
    for (final tool in ToolkitTool.values) toolTitle(tool, mode, status),
  documentsErrorTitle,
];

void main() {
  final banned = RegExp(
    r'\b(deadline|apply|applying|applied|applications?)\b',
    caseSensitive: false,
  );

  test('discover and explore never talk about deadlines or applying', () {
    for (final mode in [YearMode.discover, YearMode.explore]) {
      for (final text in _strings(mode)) {
        expect(text, isNot(matches(banned)), reason: '$mode: $text');
      }
    }
  });

  test('explore copy invites the student to try', () {
    expect(
      _strings(YearMode.explore).where((s) => s.toLowerCase().contains('try')),
      isNotEmpty,
    );
    expect(toolkitSubtitle(YearMode.explore), contains('Try'));
  });

  test('titles are in sentence case', () {
    const kept = {'CV', 'AI', 'Tack'};
    for (final mode in YearMode.values) {
      for (final title in _titles(mode)) {
        final words = title.split(' ').skip(1);
        for (final word in words) {
          if (kept.contains(word.replaceAll(RegExp(r'[^A-Za-z]'), ''))) {
            continue;
          }
          expect(word, word.toLowerCase(), reason: '$mode: $title');
        }
      }
    }
  });

  test('the allowance note says what is left, never the limit', () {
    for (final used in [0, 1, 3, 4]) {
      final note = allowanceNote(AiAllowance(used: used, limit: 4));
      expect(note, isNot(contains(' of ')));
      expect(note, endsWith('More arrive at midnight.'));
    }
    expect(
      allowanceNote(const AiAllowance(used: 1, limit: 8)),
      '7 AI actions left today. Tools marked free never use one. More arrive '
      'at midnight.',
    );
  });

  group('the words the plan fixes', () {
    const loaded = ToolkitStatus(
      documentCount: 2,
      cvCount: 1,
      hasCheckableCv: true,
      dueCount: 3,
    );

    test('the interview, by year', () {
      expect(
        toolTitle(ToolkitTool.interview, YearMode.explore, loaded),
        'Try a practice interview',
      );
      expect(
        toolTitle(ToolkitTool.interview, YearMode.build, loaded),
        'Practise an interview',
      );
      expect(
        toolTitle(ToolkitTool.interview, YearMode.launch, loaded),
        'Practise for interviews',
      );
    });

    test('practise again counts what is due', () {
      expect(
        toolBody(ToolkitTool.practiseAgain, YearMode.launch, loaded),
        '3 answers are ready to try again.',
      );
      expect(
        toolBody(
          ToolkitTool.practiseAgain,
          YearMode.launch,
          const ToolkitStatus(dueCount: 1),
        ),
        'One answer is ready to try again.',
      );
      expect(isFree(ToolkitTool.practiseAgain), isTrue);
      expect(isFree(ToolkitTool.cvCheck), isTrue);
      expect(isFree(ToolkitTool.analyser), isFalse);
    });

    test('the builder, by how many CVs there are', () {
      ToolkitStatus cvs(int n) => ToolkitStatus(documentCount: n, cvCount: n);
      expect(
        toolTitle(ToolkitTool.cvBuilder, YearMode.explore, cvs(0)),
        'Start your CV',
      );
      expect(
        toolTitle(ToolkitTool.cvBuilder, YearMode.build, cvs(0)),
        'Build your first CV',
      );
      expect(
        toolTitle(ToolkitTool.cvBuilder, YearMode.prove, cvs(0)),
        'Make your CV',
      );
      expect(
        toolTitle(ToolkitTool.cvBuilder, YearMode.launch, cvs(2)),
        'Build another CV in Tack',
      );
    });

    test('the documents, by what is saved', () {
      String body(YearMode mode, int files, int cvs) => toolBody(
        ToolkitTool.documents,
        mode,
        ToolkitStatus(documentCount: files, cvCount: cvs),
      );
      expect(
        body(YearMode.discover, 0, 0),
        'Keep certificates and results safe. Only you can see them.',
      );
      expect(
        body(YearMode.build, 0, 0),
        'Add your CV, certificates and transcripts. Only you can see them.',
      );
      expect(
        body(YearMode.build, 1, 0),
        'One file saved. Add your CV here too.',
      );
      expect(
        body(YearMode.build, 3, 0),
        '3 files saved. Add your CV here too.',
      );
      expect(body(YearMode.discover, 3, 0), '3 files, kept private.');
      expect(
        body(YearMode.launch, 1, 1),
        'One file, kept private, including '
        'your CV.',
      );
      expect(
        body(YearMode.launch, 3, 1),
        '3 files, kept private, including your CV.',
      );
    });
  });
}
