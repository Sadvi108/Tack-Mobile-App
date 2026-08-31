import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/coach/presentation/coach_screen.dart';

import 'features/coach/coach_screen_test.dart' as fx;
import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('empty coach', (tester) async {
    await shoot(tester, const CoachScreen(), 'coach-empty',
        const Size(390, 844), overrides: fx.overrides());
  });

  testWidgets('a real conversation', (tester) async {
    await shoot(tester, const CoachScreen(), 'coach-chat',
        const Size(390, 844),
        overrides: fx.overrides(
          remaining: 2,
          history: [
            fx.msg('student', 'What should I do next?'),
            fx.msg('coach',
                'The biggest win right now is your CV — worth 13 points. '
                'After that, projects (10) and your skills (6).\n\n'
                'On your roadmap, the next step is "Learn TypeScript basics".',
                answeredBy: 'data'),
            fx.msg('student', 'Is a to-do app good enough for my CV?'),
            fx.msg('coach',
                'A simple to-do app is usually too basic for a backend '
                'developer role. Since you have 0 out of 10 project points, '
                'building one can work if you focus purely on the backend.\n\n'
                'Add user authentication, connect it to a SQL database, and '
                'build full REST endpoints. That proves your Python and SQL.',
                answeredBy: 'model'),
          ],
        ));
  });
}
