import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';
import '../../../routing/router.dart';

/// The free CV check, opened without naming a CV.
class CvCheckEntryScreen extends StatelessWidget {
  const CvCheckEntryScreen({super.key});

  @override
  Widget build(BuildContext context) => TackScaffold(
    header: TackHeader(
      title: 'Free CV check',
      onBack: () => tackBack(context, fallback: Routes.vault),
    ),
    body: const SizedBox.shrink(),
  );
}
