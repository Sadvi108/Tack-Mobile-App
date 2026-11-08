import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/toolkit/application/toolkit_layout.dart';
import 'package:tack/features/toolkit/application/toolkit_status.dart';
import 'package:tack/features/toolkit/application/toolkit_tools.dart';

const _full = ToolkitStatus(
  documentCount: 4,
  cvCount: 1,
  hasCheckableCv: true,
  dueCount: 2,
);

List<ToolkitSection> _order(YearMode mode, [ToolkitStatus status = _full]) => [
  for (final (section, _) in toolkitLayout(mode, status)) section,
];

List<ToolkitTool> _tools(YearMode mode, [ToolkitStatus status = _full]) => [
  for (final (_, tools) in toolkitLayout(mode, status)) ...tools,
];

/// Records compare their lists by identity, so flatten for a deep compare.
List<List<Object>> _flat(List<(ToolkitSection, List<ToolkitTool>)> layout) => [
  for (final (section, tools) in layout) [section, ...tools],
];

void main() {
  test('each mode leads with what that year needs', () {
    const practise = ToolkitSection.practise;
    const check = ToolkitSection.check;
    const store = ToolkitSection.store;
    const ask = ToolkitSection.ask;
    expect(_order(YearMode.discover), [ask, check, store]);
    expect(_order(YearMode.explore), [ask, check, practise, store]);
    expect(_order(YearMode.build), [store, practise, check, ask]);
    expect(_order(YearMode.prove), [check, store, practise, ask]);
    expect(_order(YearMode.launch), [practise, check, store, ask]);
    expect(_order(YearMode.graduate), [practise, check, store, ask]);
  });

  test('the full layout for a final-year with everything loaded', () {
    expect(_flat(toolkitLayout(YearMode.launch, _full)), [
      [
        ToolkitSection.practise,
        ToolkitTool.interview,
        ToolkitTool.practiseAgain,
      ],
      [ToolkitSection.check, ToolkitTool.analyser, ToolkitTool.cvCheck],
      [ToolkitSection.store, ToolkitTool.documents, ToolkitTool.cvBuilder],
      [ToolkitSection.ask, ToolkitTool.coach],
    ]);
  });

  test('discover never practises, checks a CV or builds one', () {
    final tools = _tools(YearMode.discover);
    for (final hidden in [
      ToolkitTool.interview,
      ToolkitTool.practiseAgain,
      ToolkitTool.cvCheck,
      ToolkitTool.cvBuilder,
    ]) {
      expect(tools, isNot(contains(hidden)), reason: hidden.name);
    }
    expect(tools, containsAll([ToolkitTool.analyser, ToolkitTool.coach]));
    expect(tools, contains(ToolkitTool.documents));
  });

  test('practise again only when something is due, under the interview', () {
    for (final due in [null, 0]) {
      expect(
        _tools(
          YearMode.launch,
          ToolkitStatus(
            documentCount: 1,
            cvCount: 1,
            hasCheckableCv: true,
            dueCount: due,
          ),
        ),
        isNot(contains(ToolkitTool.practiseAgain)),
      );
    }
    final (_, practise) = toolkitLayout(YearMode.build, _full)[1];
    expect(practise, [ToolkitTool.interview, ToolkitTool.practiseAgain]);
  });

  test('the CV check only when a CV it can read is saved', () {
    for (final checkable in [null, false]) {
      expect(
        _tools(
          YearMode.prove,
          ToolkitStatus(
            documentCount: 1,
            cvCount: 1,
            hasCheckableCv: checkable,
          ),
        ),
        isNot(contains(ToolkitTool.cvCheck)),
      );
    }
    expect(_tools(YearMode.prove), contains(ToolkitTool.cvCheck));
  });

  test('the builder hides at three CVs and while the count is unknown', () {
    ToolkitStatus cvs(int? n) => ToolkitStatus(documentCount: n, cvCount: n);
    expect(_tools(YearMode.build, cvs(0)), contains(ToolkitTool.cvBuilder));
    expect(_tools(YearMode.build, cvs(2)), contains(ToolkitTool.cvBuilder));
    expect(
      _tools(YearMode.build, cvs(3)),
      isNot(contains(ToolkitTool.cvBuilder)),
    );
    expect(
      _tools(YearMode.build, cvs(null)),
      isNot(contains(ToolkitTool.cvBuilder)),
    );
  });

  test('nothing loaded still shows the tools that need no data', () {
    const unknown = ToolkitStatus();
    expect(_flat(toolkitLayout(YearMode.explore, unknown)), [
      [ToolkitSection.ask, ToolkitTool.coach],
      [ToolkitSection.check, ToolkitTool.analyser],
      [ToolkitSection.practise, ToolkitTool.interview],
      [ToolkitSection.store, ToolkitTool.documents],
    ]);
  });

  test('a section with nothing in it is dropped', () {
    for (final mode in YearMode.values) {
      for (final (section, tools) in toolkitLayout(
        mode,
        const ToolkitStatus(),
      )) {
        expect(tools, isNotEmpty, reason: '$mode $section');
      }
    }
  });

  test('every tool opens where it says, and records a known name', () {
    expect(
      {for (final t in ToolkitTool.values) t.analyticsName},
      {
        'interview',
        'practise_again',
        'analyser',
        'cv_check',
        'cv_builder',
        'documents',
        'coach',
      },
    );
    expect(ToolkitTool.interview.route, '/interview');
    expect(ToolkitTool.practiseAgain.route, '/interview/review');
    expect(ToolkitTool.analyser.route, '/analyser');
    expect(ToolkitTool.cvCheck.route, '/vault/check');
    expect(ToolkitTool.cvBuilder.route, '/cv-builder');
    expect(ToolkitTool.documents.route, '/vault');
    expect(ToolkitTool.coach.route, '/coach');
  });
}
