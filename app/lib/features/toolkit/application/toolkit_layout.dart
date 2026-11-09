import 'toolkit_status.dart';
import 'toolkit_tools.dart';

/// Which sections the hub shows, in what order, and the tools in each.
///
/// Pure, so every mode and every loading state is testable without a widget.
/// The order is the year's priority: a first-year asks and looks around, a
/// second-year builds a CV and practises, a third-year checks how close they
/// are, a final-year practises first. A section with nothing in it is dropped.
List<(ToolkitSection, List<ToolkitTool>)> toolkitLayout(
  YearMode mode,
  ToolkitStatus status,
) {
  const practise = ToolkitSection.practise;
  const check = ToolkitSection.check;
  const store = ToolkitSection.store;
  const ask = ToolkitSection.ask;

  final order = switch (mode) {
    YearMode.discover => [ask, check, store],
    YearMode.explore => [ask, check, practise, store],
    YearMode.build => [store, practise, check, ask],
    YearMode.prove => [check, store, practise, ask],
    YearMode.launch || YearMode.graduate => [practise, check, store, ask],
  };

  // Still at school: interview practice, the CV check and the builder are
  // for later, so they are not offered at all.
  final atSchool = mode == YearMode.discover;
  final cvCount = status.cvCount;

  List<ToolkitTool> tools(ToolkitSection section) => switch (section) {
    ToolkitSection.practise => [
      if (!atSchool) ToolkitTool.interview,
      if (!atSchool && (status.dueCount ?? 0) > 0) ToolkitTool.practiseAgain,
    ],
    ToolkitSection.check => [
      ToolkitTool.analyser,
      if (!atSchool && status.hasCheckableCv == true) ToolkitTool.cvCheck,
    ],
    ToolkitSection.store => [
      ToolkitTool.documents,
      // Three CVs is the most the documents hold.
      if (!atSchool && cvCount != null && cvCount < 3) ToolkitTool.cvBuilder,
    ],
    ToolkitSection.ask => [ToolkitTool.coach],
  };

  return [
    for (final section in order)
      if (tools(section) case final list when list.isNotEmpty) (section, list),
  ];
}
