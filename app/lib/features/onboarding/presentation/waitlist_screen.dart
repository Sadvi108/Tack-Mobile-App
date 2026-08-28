import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../auth/data/validators.dart';
import '../application/intake_controller.dart';

/// Where a student too young for Tack stops.
///
/// No account, no profile, one email. Tack is built around choosing a subject,
/// building skills and finding a first job, and none of that is useful to a
/// twelve-year-old — saying so is more respectful than letting them fill in
/// five screens for a plan they cannot use.
///
/// The words rejected, denied and ineligible appear nowhere. This is a "not
/// yet", and it is true.
class WaitlistScreen extends ConsumerStatefulWidget {
  const WaitlistScreen({super.key, required this.reason});

  final WaitlistReason reason;

  @override
  ConsumerState<WaitlistScreen> createState() => _WaitlistScreenState();
}

enum WaitlistReason {
  /// They chose primary school.
  tooEarly,

  /// Their age says under 13, which is a line Tack will not cross.
  tooYoung,
}

class _WaitlistScreenState extends ConsumerState<WaitlistScreen> {
  final _email = TextEditingController();
  String? _error;
  bool _joined = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() => _error = AuthValidators.email(_email.text));
    if (_error != null) return;

    final ok = await ref
        .read(intakeControllerProvider.notifier)
        .joinWaitlist(_email.text);
    if (!mounted) return;
    if (ok) setState(() => _joined = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intakeControllerProvider).value;
    final busy = state?.busy ?? false;

    if (_joined) {
      return TackScaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: TackSpace.xxl),
            const TackLogo(width: 52),
            const SizedBox(height: TackSpace.xl),
            Text('Thank you — we have it', style: TackText.screenTitle),
            const SizedBox(height: TackSpace.md),
            Text(
              'We will write to you when Tack is ready for you. Nothing else, '
              'and nothing to anyone else.',
              style: TackText.bodyMuted,
            ),
            const SizedBox(height: TackSpace.xl),
            TackCard(
              background: TackColors.tealTint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('In the meantime', style: TackText.cardTitle),
                  const SizedBox(height: TackSpace.sm),
                  Text(
                    'Read things that are slightly too hard for you, and finish '
                    'what you start. That is most of it, and it needs no app.',
                    style: TackText.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final tooYoung = widget.reason == WaitlistReason.tooYoung;

    return TackScaffold(
      pinnedCta: TackButton(
        'Tell me when it is ready',
        loading: busy,
        onPressed: _join,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: TackSpace.xl),
          const TackLogo(width: 52),
          const SizedBox(height: TackSpace.xl),

          Text(
            tooYoung
                ? 'Come back in a few years'
                : 'Tack is not built for you yet',
            style: TackText.screenTitle,
          ),
          const SizedBox(height: TackSpace.md),

          Text(
            tooYoung
                ? 'Tack is for students aged 13 and above, so we are not able to '
                      'set up an account for you yet. That is a rule we hold to '
                      'rather than a judgement about you.'
                : 'Everything in Tack is about choosing a subject, building skills '
                      'and finding a first job. That is still a few years away for '
                      'you, and we would rather say so than have you fill in forms '
                      'for a plan you cannot use yet.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.md),
          Text(
            'If you leave an email, we will tell you when it is worth coming '
            'back. We will not use it for anything else.',
            style: TackText.bodyMuted,
          ),
          const SizedBox(height: TackSpace.xl),

          TackTextField(
            label: 'Email',
            hint: 'you@example.com',
            controller: _email,
            errorText: _error,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _join(),
          ),

          if (state?.failure != null) ...[
            const SizedBox(height: TackSpace.md),
            Text(state!.failure!.message, style: TackText.fieldError),
          ],

          const SizedBox(height: TackSpace.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: TackIcon(
                  TackIcons.shield,
                  size: 17,
                  color: TackColors.muted,
                ),
              ),
              const SizedBox(width: TackSpace.sm),
              Expanded(
                child: Text(
                  'No account is created and nothing else is stored.',
                  style: TackText.meta.copyWith(fontSize: 13.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
