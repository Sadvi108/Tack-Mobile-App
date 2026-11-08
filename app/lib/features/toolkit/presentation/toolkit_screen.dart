import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/allowance.dart';
import '../../../core/offline/sync.dart';
import '../../../design/tack.dart';
import '../../../routing/router.dart';
import '../application/toolkit_analytics.dart';
import '../application/toolkit_copy.dart';
import '../application/toolkit_layout.dart';
import '../application/toolkit_status.dart';
import '../application/toolkit_tools.dart';
import 'tool_card.dart';

/// The Toolkit tab: everything a student uses to get ready, in one place.
///
/// A hub has no single action, so there is no pinned CTA. Loading never
/// blocks: the tools that need no data render at once, the documents card
/// waits behind a skeleton, and a card whose data failed is hidden or says so
/// without taking the rest of the screen with it.
class ToolkitScreen extends ConsumerWidget {
  const ToolkitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    final status = ref.watch(toolkitStatusProvider);
    final documents = ref.watch(documentsProvider);
    final allowance = ref.watch(aiAllowanceProvider);
    final online = ref.watch(isOnlineProvider);
    final queued = ref.watch(pendingChangesProvider).value ?? 0;

    void open(ToolkitTool tool) {
      ref.read(toolOpenedProvider)(
        tool,
        ToolSource.toolkit,
        count: tool == ToolkitTool.practiseAgain ? status.dueCount : null,
      );
      tackOpen(context, tool.route);
    }

    Widget card(ToolkitTool tool) {
      if (tool == ToolkitTool.documents) {
        if (documents.hasError) {
          return TackErrorState(
            title: documentsErrorTitle,
            body: documentsErrorBody,
            onRetry: () => ref.invalidate(documentsProvider),
          );
        }
        if (status.documentCount == null) {
          return const TackSkeleton(height: 76, radius: 18);
        }
      }
      return ToolCard(
        tool: tool,
        title: toolTitle(tool, mode, status),
        body: toolBody(tool, mode, status),
        free: isFree(tool),
        onTap: () => open(tool),
      );
    }

    final sections = toolkitLayout(mode, status);
    final left = allowance.hasError ? null : allowance.value;

    return TackScaffold(
      // The body brings its own ListView so it can pull to refresh.
      scrollable: false,
      header: TackHeader(title: toolkitTitle, subtitle: toolkitSubtitle(mode)),
      body: RefreshIndicator(
        color: TackColors.maroonText,
        onRefresh: () async {
          ref
            ..invalidate(documentsProvider)
            ..invalidate(dueQuestionsProvider)
            ..invalidate(aiAllowanceProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: TackSpace.xl),
          children: [
            if (!online) ...[
              TackOfflineState(queuedChanges: queued),
              const SizedBox(height: TackSpace.xl),
            ],
            for (final (index, (section, tools)) in sections.indexed) ...[
              if (index > 0) const SizedBox(height: TackSpace.xl),
              Text(sectionTitle(section, mode), style: TackText.sectionHeader),
              const SizedBox(height: TackSpace.md),
              for (final (i, tool) in tools.indexed) ...[
                if (i > 0) const SizedBox(height: TackSpace.row),
                card(tool),
              ],
            ],
            if (left != null) ...[
              const SizedBox(height: TackSpace.xl),
              if (left.isSpent)
                TackQuotaState(
                  resetsAt: 'midnight',
                  onGoToRoadmap: () => tackOpen(context, Routes.roadmap),
                )
              else
                _AllowanceNote(allowance: left),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllowanceNote extends StatelessWidget {
  const _AllowanceNote({required this.allowance});

  final AiAllowance allowance;

  @override
  // On the plain card: muted text on a tint is not a pair held to AA.
  Widget build(BuildContext context) => TackCard(
    compact: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(allowanceLabel, style: TackText.monoLabel),
        const SizedBox(height: TackSpace.xs),
        Text(allowanceNote(allowance), style: TackText.bodyMuted),
      ],
    ),
  );
}
