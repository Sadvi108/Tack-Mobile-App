import 'package:flutter/material.dart';

import '../design/tack.dart';

/// Shown when the app cannot start at all.
///
/// Without this a failure before `runApp` leaves a blank white screen: the
/// student has no idea whether the app is broken, their connection is down,
/// or their phone is being slow, and nothing tells them to try again. A
/// readable screen costs almost nothing and is the difference between a
/// reinstall and a retry.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTackTheme(),
      home: TackScaffold(
        padBody: false,
        scrollable: false,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: TackSpace.screenWide),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TackLogo(width: 52),
              const SizedBox(height: TackSpace.xl),
              Text('Tack could not start', style: TackText.screenTitle),
              const SizedBox(height: TackSpace.md),
              Text(
                'This is usually a connection problem rather than anything you did. '
                'Check your internet and try again.',
                style: TackText.bodyMuted,
              ),
              const SizedBox(height: TackSpace.xl),
              TackButton('Try again', onPressed: onRetry),
              const SizedBox(height: TackSpace.md),
              Text(
                'If it keeps happening, your saved work is safe — it is stored on '
                'this phone and on your account, not in the app itself.',
                style: TackText.meta.copyWith(fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
