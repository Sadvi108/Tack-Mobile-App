import '../../../design/tack.dart';
import '../../../routing/routes.dart';

/// The four kinds of thing a student does to get ready.
enum ToolkitSection {
  practise,
  check,

  /// Keep: the documents, and the builder that makes a CV to keep there.
  store,
  ask,
}

/// Every tool the hub can show, where it opens and what it records.
enum ToolkitTool {
  interview(
    route: Routes.interview,
    icon: TackIcons.practice,
    analyticsName: 'interview',
    section: ToolkitSection.practise,
  ),
  practiseAgain(
    route: Routes.interviewReview,
    icon: TackIcons.refresh,
    analyticsName: 'practise_again',
    section: ToolkitSection.practise,
  ),
  analyser(
    route: Routes.analyser,
    icon: TackIcons.search,
    analyticsName: 'analyser',
    section: ToolkitSection.check,
  ),
  cvCheck(
    route: Routes.cvCheck,
    icon: TackIcons.check,
    analyticsName: 'cv_check',
    section: ToolkitSection.check,
  ),
  cvBuilder(
    route: Routes.cvBuilder,
    icon: TackIcons.edit,
    analyticsName: 'cv_builder',
    section: ToolkitSection.store,
  ),
  documents(
    route: Routes.vault,
    icon: TackIcons.vault,
    analyticsName: 'documents',
    section: ToolkitSection.store,
  ),
  coach(
    route: Routes.coach,
    icon: TackIcons.coach,
    analyticsName: 'coach',
    section: ToolkitSection.ask,
  );

  const ToolkitTool({
    required this.route,
    required this.icon,
    required this.analyticsName,
    required this.section,
  });

  /// Opened with `tackOpen`: `/vault` switches to the documents inside the
  /// Toolkit branch, everything else covers the bar.
  final String route;
  final String icon;

  /// The `tool` value recorded by `tool_opened` (an allowlisted id).
  final String analyticsName;
  final ToolkitSection section;
}
