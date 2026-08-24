import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/tack.dart';
import 'routing/router.dart';

class TackApp extends ConsumerWidget {
  const TackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Tack',
      debugShowCheckedModeBanner: false,
      theme: buildTackTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // The design is fixed at a 360px baseline and audited at 16px body
        // text. Honour the user's larger text sizes, but cap the scale so the
        // pinned CTA cannot be pushed off a short screen.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
