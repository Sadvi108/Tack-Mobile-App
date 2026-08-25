import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failure.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../../roadmap/data/roadmap_repository.dart';
import '../data/career_path.dart';
import '../data/path_repository.dart';

/// One career path in full: what the job is, who it suits, what it needs, and
/// how far along the student already is.
class PathDetailScreen extends ConsumerStatefulWidget {
  const PathDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<PathDetailScreen> createState() => _PathDetailScreenState();
}

class _PathDetailScreenState extends ConsumerState<PathDetailScreen> {
  bool _busy = false;

  Future<void> _follow(PathMatch match) async {
    setState(() => _busy = true);
    try {
      await ref.read(pathRepositoryProvider).choose(match.path.id);
      await ref
          .read(roadmapRepositoryProvider)
          .generateFromPath(match.path.id, match.path.title);
      ref
        ..invalidate(chosenPathsProvider)
        ..invalidate(roadmapsProvider);
      if (!mounted) return;
      TackToast.show(
        context,
        message: 'Following ${match.path.title}. Your roadmap is ready.',
        actionLabel: 'Open',
        onAction: () => context.go(Routes.roadmap),
      );
    } catch (e) {
      if (!mounted) return;
      TackToast.show(
        context,
        message: Failure.from(e).message,
        kind: TackToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unfollow(String pathId, String title) async {
    final confirmed = await confirmTackAction(
      context,
      title: 'Stop following $title?',
      body: 'Your roadmap for it stays saved, so you can pick it up again later.',
      confirmLabel: 'Stop following',
    );
    if (!confirmed || !mounted) return;

    await ref.read(pathRepositoryProvider).unfollow(pathId);
    ref.invalidate(chosenPathsProvider);
    if (mounted) TackToast.show(context, message: 'No longer following $title.');
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(pathMatchesProvider);
    final chosen = ref.watch(chosenPathsProvider).value ?? const <ChosenPath>[];

    return matches.when(
      loading: () => TackScaffold(
        header: TackHeader(title: 'Path', onBack: () => context.pop()),
        body: const TackSkeleton(height: 320, radius: 20),
      ),
      error: (_, _) => TackScaffold(
        header: TackHeader(title: 'Path', onBack: () => context.pop()),
        body: TackErrorState(
          body: 'This path did not load. Check your connection and try again.',
          onRetry: () => ref.invalidate(careerPathsProvider),
        ),
      ),
      data: (all) {
        final match = all.where((m) => m.path.slug == widget.slug).firstOrNull;
        if (match == null) {
          return TackScaffold(
            header: TackHeader(title: 'Path', onBack: () => context.pop()),
            body: const TackErrorState(
              title: 'That path is not here',
              body: 'Go back to the list and pick another one.',
            ),
          );
        }

        final path = match.path;
        final following = chosen.any((c) => c.pathId == path.id);

        return TackScaffold(
          header: TackHeader(title: path.title, onBack: () => context.pop()),
          pinnedCta: following
              ? TackButton.secondary(
                  'Stop following',
                  onPressed: () => _unfollow(path.id, path.title),
                )
              : TackButton(
                  'Follow this path',
                  loading: _busy,
                  onPressed: () => _follow(match),
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(path.summary, style: TackText.bodyLarge),
              const SizedBox(height: TackSpace.lg),

              TackCard(
                child: Row(
                  children: [
                    Expanded(
                      child: _Fact(label: 'Starting pay', value: path.salaryLabel),
                    ),
                    const SizedBox(width: TackSpace.md),
                    Expanded(
                      child: _Fact(label: 'Job-ready in', value: path.timeLabel),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              TackCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Where you stand', style: TackText.cardTitle)),
                        TackPill.teal('${match.percent}%'),
                      ],
                    ),
                    const SizedBox(height: TackSpace.md),
                    TackProgressBar(value: match.percent / 100, height: 8),
                    const SizedBox(height: TackSpace.sm),
                    Text(
                      match.have.isEmpty
                          ? 'None of the skills yet. That is normal, and the roadmap starts from zero.'
                          : 'You already have ${match.have.length} of the ${match.total} skills this path asks for.',
                      style: TackText.bodyMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TackSpace.stackLoose),

              if (path.dayToDay.isNotEmpty) ...[
                Text('What the job actually is', style: TackText.sectionHeader),
                const SizedBox(height: TackSpace.md),
                TackCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in path.dayToDay)
                        Padding(
                          padding: const EdgeInsets.only(bottom: TackSpace.sm),
                          child: Text('· $item', style: TackText.body),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: TackSpace.stackLoose),
              ],

              if (path.goodFitIf.isNotEmpty) ...[
                Text('It suits you if', style: TackText.sectionHeader),
                const SizedBox(height: TackSpace.md),
                TackCard(
                  background: TackColors.tealTint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in path.goodFitIf)
                        Padding(
                          padding: const EdgeInsets.only(bottom: TackSpace.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: TackIcon(TackIcons.check,
                                    size: 17, color: TackColors.tealText),
                              ),
                              const SizedBox(width: TackSpace.sm),
                              Expanded(child: Text(item, style: TackText.body)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: TackSpace.stackLoose),
              ],

              Text('Skills it asks for', style: TackText.sectionHeader),
              const SizedBox(height: TackSpace.md),
              for (final importance in SkillImportance.values)
                _SkillGroup(
                  importance: importance,
                  skills: path.skills.where((s) => s.importance == importance).toList(),
                  have: match.have.map((s) => s.skillId).toSet(),
                ),

              const SizedBox(height: TackSpace.xl),
            ],
          ),
        );
      },
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TackText.monoLabelSmall),
        const SizedBox(height: 6),
        Text(value, style: TackText.rowTitle),
      ],
    );
  }
}

class _SkillGroup extends StatelessWidget {
  const _SkillGroup({
    required this.importance,
    required this.skills,
    required this.have,
  });

  final SkillImportance importance;
  final List<PathSkill> skills;
  final Set<String> have;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: TackSpace.stack),
      child: TackCard(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(importance.label.toUpperCase(), style: TackText.monoLabelSmall),
            const SizedBox(height: TackSpace.md),
            Wrap(
              spacing: TackSpace.sm,
              runSpacing: TackSpace.sm,
              children: [
                for (final skill in skills)
                  have.contains(skill.skillId)
                      ? TackPill.teal(skill.name)
                      : TackPill(
                          skill.name,
                          background: TackColors.line,
                          foreground: TackColors.muted,
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
