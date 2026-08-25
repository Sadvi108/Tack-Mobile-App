import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/crash_reporting.dart';
import 'core/supabase/client.dart';

Future<void> main() async {
  // Wraps everything, so an error during startup is reported rather than
  // showing a student a grey screen with no trace of why.
  await CrashReporting.run(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // The app is portrait-only: every screen is designed at 360px wide and a
    // landscape layout was never drawn.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    await initSupabase();

    runApp(const ProviderScope(child: TackApp()));
  });
}
