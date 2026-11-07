import 'package:flutter/widgets.dart';

import '../../../design/tack.dart';

/// The Toolkit tab: everything a student uses to get ready, in one place.
class ToolkitScreen extends StatelessWidget {
  const ToolkitScreen({super.key});

  @override
  Widget build(BuildContext context) => const TackScaffold(
    header: TackHeader(title: 'Your toolkit'),
    body: SizedBox.shrink(),
  );
}
