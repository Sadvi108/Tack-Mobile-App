import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../profile/application/profile.dart';
import 'toolkit_tools.dart';

/// Where a tool was opened from. Recorded as `source`, an allowlisted id.
enum ToolSource { toolkit, home, coach, application, score }

/// Records that a tool was opened. [count] is kept only for practise again,
/// where it is how many answers were due.
typedef ToolOpened =
    void Function(ToolkitTool tool, ToolSource source, {int? count});

/// Records `tool_opened {tool, source, mode, count?}`: fixed ids and a count,
/// never a title. Tests override it with a recorder.
final toolOpenedProvider = Provider<ToolOpened>(
  (ref) =>
      (tool, source, {count}) => ref
          .read(analyticsProvider)
          .track(
            'tool_opened',
            properties: {
              'tool': tool.analyticsName,
              'source': source.name,
              'mode': ref.read(modeProvider).name,
              if (count != null && tool == ToolkitTool.practiseAgain)
                'count': count,
            },
          )
          .ignore(),
);
