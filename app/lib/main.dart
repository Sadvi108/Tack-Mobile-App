import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/crash_reporting.dart';
import 'core/startup_failure.dart';
import 'core/supabase/client.dart';

Future<void> main() async {
  // Wraps everything, so a failure during startup is reported rather than
  // leaving a student staring at a blank screen with no trace of why.
  await CrashReporting.run(_start);
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is portrait-only: every screen is designed at 360px wide and a
  // landscape layout was never drawn.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await initSupabase();
  } catch (error, stack) {
    // Reported explicitly rather than left to the zone handler, because this
    // is the one failure a student can neither see nor work around.
    await CrashReporting.report(error, stack, context: {'phase': 'startup'});
    runApp(StartupFailureApp(onRetry: () => _start()));
    return;
  }

  runApp(const ProviderScope(child: TackApp()));
}
