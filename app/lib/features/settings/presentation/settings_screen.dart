import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/failure.dart';
import '../../../core/offline/sync.dart';
import '../../../core/policy_links.dart';
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
  bool _syncing = false;

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

  /// Shown while a manual sync is in flight, so the tap visibly did
  /// something even when there was nothing to send.
  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).flush();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
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
        onBack: () => tackBack(context, fallback: Routes.profile),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccountCard(
            name: profile?.fullName,
            email: user?.email,
            initials: profile?.initials ?? '–',
          ),
          const SizedBox(height: TackSpace.stackLoose),

          _Section('ACCOUNT'),
          TackCard(
            child: Column(
              children: [
                if (profile?.phone case final phone?) ...[
                  _Row(
                    icon: TackIcons.phone,
                    tone: _Tone.blue,
                    label: 'Phone',
                    value: '${profile?.dialCode ?? ''} $phone'.trim(),
                  ),
                  const _Divider(),
                ],
                _Tap(
                  icon: TackIcons.shield,
                  tone: _Tone.maroon,
                  label: 'Change password',
                  hint: 'You will need your current one',
                  onTap: _changePassword,
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.edit,
                  tone: _Tone.teal,
                  label: 'Edit your details',
                  hint: 'Name, phone, university, skills',
                  onTap: () => context.go(Routes.profile),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          // Three answers, all on screen: picking one is a tap, and the page
          // repaints in it straight away, so the choice explains itself.
          _Section('APPEARANCE'),
          TackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TackSegmented<Appearance>(
                  segments: [
                    for (final option in Appearance.values)
                      TackSegment(
                        value: option,
                        label: _short(option),
                        icon: switch (option) {
                          Appearance.system => TackIcons.phone,
                          Appearance.light => TackIcons.sun,
                          Appearance.dark => TackIcons.moon,
                        },
                      ),
                  ],
                  selected: appearance,
                  onChanged: (picked) =>
                      ref.read(appearanceProvider.notifier).choose(picked),
                ),
                const SizedBox(height: TackSpace.md),
                AnimatedSwitcher(
                  duration: TackMotion.normal,
                  child: Text(
                    appearance.blurb,
                    key: ValueKey(appearance),
                    style: TackText.meta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          _Section('YOUR DATA'),
          TackCard(
            child: Column(
              children: [
                _Row(
                  icon: TackIcons.clock,
                  tone: queued == 0 ? _Tone.neutral : _Tone.amber,
                  label: 'Waiting to sync',
                  value: queued == 0
                      ? 'Nothing'
                      : '$queued ${queued == 1 ? 'change' : 'changes'}',
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.file,
                  tone: _Tone.blue,
                  label: 'Review saved changes',
                  hint: 'Resolve changes made on two devices',
                  onTap: () => context.push('/settings/sync'),
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.refresh,
                  tone: _Tone.teal,
                  label: 'Try syncing now',
                  hint: 'Saved changes stay here until they are sent',
                  busy: _syncing,
                  onTap: _syncNow,
                ),
                const _Divider(),
                _Row(
                  icon: online ? TackIcons.check : TackIcons.offline,
                  tone: online ? _Tone.teal : _Tone.amber,
                  label: 'Connection',
                  value: online ? 'Online' : 'Offline',
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.vault,
                  tone: _Tone.maroon,
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
                  _Row(
                    icon: TackIcons.info,
                    tone: _Tone.neutral,
                    label: 'Version',
                    value: version,
                  ),
                  const _Divider(),
                ],
                _Row(
                  icon: TackIcons.star,
                  tone: _Tone.amber,
                  label: 'Made for',
                  value: 'Bangladeshi students',
                ),
                const _Divider(),
                // These three leave the app, and say so with their arrow.
                _Tap(
                  icon: TackIcons.shield,
                  tone: _Tone.blue,
                  label: 'Privacy policy',
                  hint: 'What we hold, and what leaves our database',
                  external: true,
                  onTap: () => PolicyLinks.open(context, PolicyLinks.privacy),
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.coach,
                  tone: _Tone.teal,
                  label: 'Support and account deletion',
                  hint: 'Contact Tack or request deletion outside the app',
                  external: true,
                  onTap: () => PolicyLinks.open(context, PolicyLinks.support),
                ),
                const _Divider(),
                _Tap(
                  icon: TackIcons.file,
                  tone: _Tone.neutral,
                  label: 'Terms of use',
                  hint: 'What Tack promises, and what it does not',
                  external: true,
                  onTap: () => PolicyLinks.open(context, PolicyLinks.terms),
                ),
              ],
            ),
          ),
          const SizedBox(height: TackSpace.stackLoose),

          TackCard(
            child: _Tap(
              icon: TackIcons.logout,
              tone: _Tone.maroon,
              label: 'Log out',
              emphasis: true,
              onTap: _signOut,
            ),
          ),
          const SizedBox(height: TackSpace.xl),

          // Last, and visually quiet. It has to be findable — Play requires a
          // route to it, and a student who wants out should not have to email
          // anybody — but it should not sit next to Log out looking like a
          // neighbour of it.
          _Section('DELETE YOUR ACCOUNT'),
          TackCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Well(icon: TackIcons.trash, tone: _Tone.danger),
                    const SizedBox(width: TackSpace.lg),
                    Expanded(
                      child: Text(
                        'This removes your profile, your roadmap, your '
                        'applications and every document you have uploaded. '
                        'It cannot be undone and there is no way to get any '
                        'of it back.',
                        style: TackText.bodyMuted,
                      ),
                    ),
                  ],
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

  /// Short enough for three to sit side by side at 360px. The sentence under
  /// the control says the rest.
  static String _short(Appearance appearance) => switch (appearance) {
    Appearance.system => 'Auto',
    Appearance.light => 'Light',
    Appearance.dark => 'Dark',
  };

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
            'to sync. They stay on this phone for this account. Log back in to send them.';
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

/// Who is signed in, at the top of the page where somebody checking it looks
/// first.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.initials,
  });

  final String? name;
  final String? email;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return TackCard(
      child: Row(
        children: [
          TackAvatar(initials: initials, size: 52),
          const SizedBox(width: TackSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? 'Signed in as', style: TackText.cardTitle),
                const SizedBox(height: 3),
                Text(email ?? 'Not signed in', style: TackText.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The colour family of a row's icon. The glyph is always the text colour of
/// its tint, so every well is a pair the contrast test already holds to AA.
enum _Tone { maroon, teal, amber, blue, neutral, danger }

class _Well extends StatelessWidget {
  const _Well({required this.icon, required this.tone});

  final String icon;
  final _Tone tone;

  static const size = 36.0;

  @override
  Widget build(BuildContext context) {
    final (well, glyph) = switch (tone) {
      _Tone.maroon => (TackColors.maroonTint, TackColors.maroonText),
      _Tone.teal => (TackColors.tealTint, TackColors.tealText),
      _Tone.amber => (TackColors.amberTint, TackColors.amberText),
      _Tone.blue => (TackColors.blueTint, TackColors.blueText),
      _Tone.neutral => (TackColors.line, TackColors.muted),
      _Tone.danger => (TackColors.line, TackColors.dangerText),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: well,
          borderRadius: TackRadius.inputAll,
        ),
        child: TackIcon(icon, size: 19, color: glyph),
      ),
    );
  }
}

/// Lines up with the text, not the icon, the way a list with leading icons
/// is divided everywhere else on a phone.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const TackDivider(indent: _Well.size + TackSpace.lg);
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
  });

  final String icon;
  final _Tone tone;
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
      child: Row(
        children: [
          _Well(icon: icon, tone: tone),
          const SizedBox(width: TackSpace.lg),
          Expanded(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TackText.rowTitle),
                      const SizedBox(height: 3),
                      Text(value, style: TackText.meta),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Text(label, style: TackText.rowTitle)),
                      const SizedBox(width: TackSpace.md),
                      // Its own width, not half the row: a short value split
                      // evenly with its label wrapped both of them.
                      Text(value, style: TackText.meta, maxLines: 1),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({
    required this.icon,
    required this.tone,
    required this.label,
    required this.onTap,
    this.hint,
    this.external = false,
    this.busy = false,
    this.emphasis = false,
  });

  final String icon;
  final _Tone tone;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  /// Opens something outside the app: an arrow out, not a chevron in.
  final bool external;

  /// Working on it: a spinner where the chevron was.
  final bool busy;

  /// The label in the brand colour, for the one row that is an action rather
  /// than a place.
  final bool emphasis;

  @override
  Widget build(BuildContext context) => TackTapRow(
    onTap: busy ? null : onTap,
    padding: const EdgeInsets.symmetric(vertical: TackSpace.md),
    child: Row(
      children: [
        _Well(icon: icon, tone: tone),
        const SizedBox(width: TackSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: emphasis
                    ? TackText.rowTitle.copyWith(
                        color: TackColors.maroonText,
                        fontWeight: FontWeight.w600,
                      )
                    : TackText.rowTitle,
              ),
              if (hint case final h?) ...[
                const SizedBox(height: 2),
                Text(h, style: TackText.meta),
              ],
            ],
          ),
        ),
        const SizedBox(width: TackSpace.sm),
        if (busy)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(TackColors.tealText),
            ),
          )
        else
          TackIcon(
            external ? TackIcons.externalLink : TackIcons.chevronRight,
            size: 18,
            color: external ? TackColors.muted : TackColors.strokeFaint,
          ),
      ],
    ),
  );
}
