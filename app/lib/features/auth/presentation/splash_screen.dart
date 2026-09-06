import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/application/profile.dart';

/// Decides where a returning student lands: onboarding if they never finished
/// it, otherwise the dashboard. Signed-out students are sent to the welcome
/// screen by the router's redirect before this ever renders.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return TackScaffold(
      padBody: false,
      scrollable: false,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const TackLogo(width: 64),
            const SizedBox(height: TackSpace.xl),
            if (profile.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TackSpace.screen,
                ),
                child: TackErrorState(
                  title: 'That did not load',
                  body: 'Check your connection and try again.',
                  onRetry: () => ref.invalidate(profileProvider),
                ),
              )
            else
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(TackColors.maroonText),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
