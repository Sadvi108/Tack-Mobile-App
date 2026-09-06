import '../config/env.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/tack.dart';

/// Public policy resources served by Tack's Supabase project.
class PolicyLinks {
  const PolicyLinks._();

  static const privacy = '${Env.supabaseUrl}/functions/v1/policies/privacy';
  static const support = '${Env.supabaseUrl}/functions/v1/policies/support';
  static const terms = '${Env.supabaseUrl}/functions/v1/policies/terms';

  /// Opens one in the browser, and says so rather than failing silently if the
  /// phone has nothing that can.
  static Future<void> open(BuildContext context, String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('browser_unavailable');
    } catch (_) {
      if (!context.mounted) return;
      TackToast.show(
        context,
        message: 'That page could not be opened.',
        kind: TackToastKind.error,
      );
    }
  }
}

/// The privacy line on the sign-up screen, with the policies linked from it.
///
/// It says both things in one sentence because that screen must fit 360x640
/// without scrolling and has no height to spare — a separate consent line
/// overflowed it by 35px. They are the same subject, so no meaning is lost by
/// putting them together.
///
/// Stateful only because a [TapGestureRecognizer] holds resources and has to
/// be disposed; a stateless version leaks one per rebuild. This is the one
/// place in the app that needs a tappable phrase inside running text, so the
/// cost is paid once here rather than turned into a component.
class PolicyNote extends StatefulWidget {
  const PolicyNote({super.key});

  @override
  State<PolicyNote> createState() => _PolicyNoteState();
}

class _PolicyNoteState extends State<PolicyNote> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()
      ..onTap = () => PolicyLinks.open(context, PolicyLinks.terms);
    _privacy = TapGestureRecognizer()
      ..onTap = () => PolicyLinks.open(context, PolicyLinks.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = TackText.meta.copyWith(fontSize: 13.5);
    final link = base.copyWith(
      color: TackColors.maroonText,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(
            text:
                'Your CV and certificates stay private. Signing up accepts '
                'our ',
          ),
          TextSpan(text: 'terms', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'privacy policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
