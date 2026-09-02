import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/failure.dart';
import '../../../core/offline/sync.dart';
import '../../../core/supabase/client.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/validators.dart';
import '../../profile/data/profile_repository.dart';
import '../data/appearance.dart';

/// Everything about the app rather than about the student's career.
///
/// Deliberately dull, and grouped the way somebody looks for things: who am I
/// signed in as, how does it look, what happens to my data, what version is
/// this. Nothing here is a feature to discover — it is a place to go when you
/// already know what you want.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _version;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // A missing version is not worth an error state; the row just hides.
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    // Outside the builder, both of them. A `var busy` declared inside is reset
    // to false by the very rebuild setSheetState schedules, so the button
    // never showed its spinner and stayed tappable through the request —
    // two taps meant two password writes.
    var busy = false;

    final done = await showTackSheet<bool>(
      context: context,
      title: 'Change your password',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> submit() async {
            if (busy) return;
            final a = next.text, b = confirm.text;
            final complaint = AuthValidators.password(a);
            if (complaint != null) {
              setSheetState(() => error = complaint);
              return;
            }
            if (a != b) {
              setSheetState(() => error = 'Those two do not match.');
              return;
            }
            setSheetState(() {
              busy = true;
              error = null;
            });
            try {
              // Proves it is really them before the password moves, so a
              // borrowed unlocked phone cannot lock the owner out of their
              // own account.
              await ref
                  .read(authRepositoryProvider)
                  .reauthenticate(current.text);
              await ref.read(authRepositoryProvider).updatePassword(a);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop(true);
            } catch (e) {
              setSheetState(() {
                busy = false;
                error = Failure.from(e).message;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: TackSpace.screen,
              right: TackSpace.screen,
              bottom:
                  MediaQuery.viewInsetsOf(sheetContext).bottom + TackSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TackTextField(
                  label: 'Your current password',
                  controller: current,
                  obscureText: true,
                ),
                const SizedBox(height: TackSpace.md),
                TackTextField(
                  label: 'New password',
                  controller: next,
                  obscureText: true,
                  helperText: 'At least 8 characters.',
                ),
                const SizedBox(height: TackSpace.md),
                TackTextField(
                  label: 'New password again',
                  controller: confirm,
                  obscureText: true,
                  errorText: error,
                ),
                const SizedBox(height: TackSpace.lg),
                TackButton('Change it', loading: busy, onPressed: submit),
              ],
            ),
          );
        },
      ),
    );

    current.dispose();
    next.dispose();
    confirm.dispose();

    if (done == true && mounted) {
      TackToast.show(context, message: 'Password changed.');
    }
  }

  Future<void> _pickAppearance() async {
    final current = ref.read(appearanceProvider).value ?? Appearance.system;
    final picked = await showTackSheet<Appearance>(
      context: context,
      title: 'Appearance',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          TackSpace.screen,
          0,
          TackSpace.screen,
          TackSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in Appearance.values) ...[
              _AppearanceOption(
                appearance: option,
                selected: option == current,
                onTap: () => Navigator.of(context).pop(option),
              ),
              if (option != Appearance.values.last)
                const SizedBox(height: TackSpace.stack),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(appearanceProvider.notifier).choose(picked);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final user = ref.watch(currentUserProvider);
    final appearance = ref.watch(appearanceProvider).value ?? Appearance.system;
    final online = ref.watch(isOnlineProvider);
    final queued = ref.watch(pendingChangesProvider).value ?? 0;

    return TackScaffold(
      header: TackHeader(
        title: 'Settings',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section('ACCOUNT'),
          TackCard(
            child: Column(
              children: [
                _Row(
                  label: 'Signed in as',
                  value: user?.email ?? 'Not signed in',
                ),
                if (profile?.phone case final phone?) ...[
                  const TackDivider(),
                  _Row(
                    label: 'Phone',
                    value: '${profile?.dialCode ?? ''} $phone'.trim(),
                  ),
                ],
                if (profile?.fullName case final name?) ...[
                  const TackDivider(),
                  _Row(label: 'Name', value: name),
                ],
                const TackDivider(),
                _Tap(
                  label: 'Change password',
                  hint: 'You will need your current one',
                  onTap: _changePassword,
                ),
                const TackDivider(),
                _Tap(
                  label: 'Edit your details',
                  hint: 'Name, phone, university, skills',
                  onTap: () => context.go(Routes.profile),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          _Section('APPEARANCE'),
          TackCard(
            child: _Tap(
              label: 'Theme',
              hint: appearance.label,
              onTap: _pickAppearance,
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          _Section('YOUR DATA'),
          TackCard(
            child: Column(
              children: [
                _Row(
                  label: 'Waiting to sync',
                  value: queued == 0
                      ? 'Nothing'
                      : '$queued ${queued == 1 ? 'change' : 'changes'}',
                ),
                const TackDivider(),
                _Row(label: 'Connection', value: online ? 'Online' : 'Offline'),
                const TackDivider(),
                _Tap(
                  label: 'Your documents',
                  hint: 'CVs and certificates you have uploaded',
                  onTap: () => context.go(Routes.vault),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.sm),
          // Said here rather than buried in a policy nobody opens.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TackSpace.xs),
            child: Text(
              'Everything Tack holds about you lives in one database that only '
              'you can read. There is no advertising, no third-party analytics '
              'and no crash service — nothing about you leaves it.',
              style: TackText.meta,
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          _Section('ABOUT'),
          TackCard(
            child: Column(
              children: [
                if (_version case final version?) ...[
                  _Row(label: 'Version', value: version),
                  const TackDivider(),
                ],
                _Row(label: 'Made for', value: 'Bangladeshi students'),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          TackButton.ghost('Log out', onPressed: _signOut),
          const SizedBox(height: TackSpace.stackLoose),

          // Last, and visually quiet. It has to be findable — Play requires a
          // route to it, and a student who wants out should not have to email
          // anybody — but it should not sit next to Log out looking like a
          // neighbour of it.
          _Section('DELETE YOUR ACCOUNT'),
          TackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This removes your profile, your roadmap, your applications '
                  'and every document you have uploaded. It cannot be undone '
                  'and there is no way to get any of it back.',
                  style: TackText.bodyMuted,
                ),
                const SizedBox(height: TackSpace.md),
                TackButton.secondary(
                  'Delete my account',
                  loading: _deleting,
                  onPressed: _deleteAccount,
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.xl),
        ],
      ),
    );
  }

  /// Typed, not tapped.
  ///
  /// Everything else in this app is reversible — a cancelled roadmap comes
  /// back with its ticks intact — and this is the one thing that is not. A
  /// single confirm button next to a "Log out" the student has pressed a dozen
  /// times is not enough friction for an action with no undo, so they write
  /// the word out.
  Future<void> _deleteAccount() async {
    final typed = TextEditingController();
    var armed = false;

    final go = await showTackSheet<bool>(
      context: context,
      title: 'Delete your account?',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: TackSpace.screen,
            right: TackSpace.screen,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + TackSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your profile, roadmap, applications, saved openings and every '
                'document you have uploaded will be deleted from our servers. '
                'This is permanent — we cannot restore it, even if you ask.',
                style: TackText.bodyMuted,
              ),
              const SizedBox(height: TackSpace.lg),
              TackTextField(
                label: 'Type DELETE to confirm',
                controller: typed,
                // Compared case-insensitively: the point is the deliberate act
                // of writing the word, not fighting a phone keyboard that
                // helpfully lower-cases it.
                onChanged: (v) {
                  final next = v.trim().toUpperCase() == 'DELETE';
                  if (next != armed) setSheetState(() => armed = next);
                },
              ),
              const SizedBox(height: TackSpace.lg),
              TackButton(
                'Delete my account',
                onPressed: armed
                    ? () => Navigator.of(sheetContext).pop(true)
                    : null,
              ),
              const SizedBox(height: TackSpace.row),
              TackButton.ghost(
                'Keep my account',
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    typed.dispose();
    if (go != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // No toast. The router sends them to the welcome screen the moment the
      // session clears, and a "deleted" message on a screen for signed-out
      // people would be talking to somebody who is no longer there.
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    }
  }

  Future<void> _signOut() async {
    final sure = await confirmTackAction(
      context,
      title: 'Log out?',
      body: queuedWarning(ref.read(pendingChangesProvider).value ?? 0),
      confirmLabel: 'Log out',
    );
    if (!sure || !mounted) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  /// Logging out with unsent changes on the phone would lose them, so the
  /// confirm says so rather than finding out afterwards.
  static String queuedWarning(int queued) => queued == 0
      ? 'Your work stays saved. You can log back in any time.'
      : 'You have $queued ${queued == 1 ? 'change' : 'changes'} still waiting '
            'to sync. Go back online first, or they will be lost.';
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: TackSpace.xs, bottom: TackSpace.sm),
    child: Text(label, style: TackText.monoLabelSmall),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  /// Beyond this, a value cannot share a line with its label at 360px.
  ///
  /// An email is the row that proves it: "nusrat@example.com" beside "Signed
  /// in as" broke after the "c" and left a lone "m" on the next line. Widening
  /// the value's share only moved the problem onto the labels, which then
  /// wrapped instead. There is no split that fits both, so long values get the
  /// full width on their own line.
  static const _tooLongToShareALine = 16;

  @override
  Widget build(BuildContext context) {
    final stacked = value.length > _tooLongToShareALine;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TackSpace.md),
      child: stacked
          // Full width, or the column shrinks to its widest line and the card
          // centres it, leaving the email adrift in the middle of the row.
          ? SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TackText.rowTitle),
                  const SizedBox(height: 3),
                  Text(value, style: TackText.meta),
                ],
              ),
            )
          : Row(
              children: [
                Expanded(child: Text(label, style: TackText.rowTitle)),
                const SizedBox(width: TackSpace.md),
                Flexible(
                  child: Text(
                    value,
                    style: TackText.meta,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({required this.label, required this.onTap, this.hint});

  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TackTapRow(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: TackSpace.md),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TackText.rowTitle),
              if (hint case final h?) ...[
                const SizedBox(height: 2),
                Text(h, style: TackText.meta),
              ],
            ],
          ),
        ),
        TackIcon(
          TackIcons.chevronRight,
          size: 18,
          color: TackColors.strokeFaint,
        ),
      ],
    ),
  );
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.appearance,
    required this.selected,
    required this.onTap,
  });

  final Appearance appearance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: TackSpace.lg,
            vertical: TackSpace.md,
          ),
          decoration: BoxDecoration(
            color: TackColors.white,
            borderRadius: TackRadius.listCardAll,
            border: Border.all(
              color: selected ? TackColors.maroon : TackColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appearance.label, style: TackText.rowTitle),
                    const SizedBox(height: 2),
                    Text(appearance.blurb, style: TackText.meta),
                  ],
                ),
              ),
              // A tick, not only a border: colour is never the only signal.
              if (selected)
                TackIcon(
                  TackIcons.check,
                  size: 18,
                  color: TackColors.maroonText,
                  strokeWidth: 3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
