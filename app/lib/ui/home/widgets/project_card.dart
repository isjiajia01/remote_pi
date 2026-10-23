import 'package:app/ui/core/interaction_feedback.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/agent_identity.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/widgets/agent_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Divider;
import 'package:lucide_icons_flutter/lucide_icons.dart';

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Header summary for a project card, e.g. "2 sessions · 1 working".
String projectSummary(HomeGroup group) {
  final parts = <String>[];
  if (group.sessions.isNotEmpty) {
    parts.add(plural(group.sessions.length, 'session'));
  }
  bool busy(HomeItem i) => i.lastKnownStatus == AgentStatus.working;
  final working =
      group.sessions.fold<int>(
        0,
        (n, s) => n + (busy(s.item) ? 1 : 0) + s.subagents.where(busy).length,
      ) +
      group.orphans.where(busy).length;
  if (working > 0) parts.add('$working working');
  final subs =
      group.sessions.fold<int>(0, (n, s) => n + s.subagents.length) +
      group.orphans.length;
  if (subs > 0) parts.add(plural(subs, 'sub-agent'));
  if (parts.isEmpty && group.offline.isNotEmpty) {
    parts.add('${group.offline.length} offline');
  }
  return parts.join(' · ');
}

/// 44pt full-width toggle row: "2 sub-agents · 1 working ⌄".
class DisclosureRow extends StatelessWidget {
  const DisclosureRow({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
    this.indent = 44,
    this.trailing,
  });
  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final double indent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            expanded: expanded,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                InteractionFeedback.selection();
                onToggle();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.only(left: indent, right: 8),
                  child: Row(
                    children: [
                      Icon(
                        expanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight,
                        size: 16,
                        color: c.ink2,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          style: context.typo.footnote.copyWith(color: c.ink2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Compact nested row for a sub-agent run: never a peer of main sessions.
class SubagentRow extends StatelessWidget {
  const SubagentRow({
    super.key,
    required this.item,
    required this.onOpen,
    this.now,
  });
  final HomeItem item;
  final VoidCallback onOpen;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = item.lastKnownStatus;
    final (model, isId) = friendlyModel(item.room.model ?? '');
    final statusText = status == AgentStatus.working
        ? 'Working'
        : status == AgentStatus.online
        ? 'Idle'
        : status.label;
    return Semantics(
      button: true,
      label: 'Sub-agent ${item.displayName}, $statusText',
      excludeSemantics: true,
      onTap: onOpen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(44, 6, 16, 6),
            child: Row(
              children: [
                StatusDot(
                  status: item.status,
                  lastKnownStatus: status,
                  size: 8,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.displayName,
                    style: context.typo.subhead.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (model.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    model,
                    style: isId
                        ? context.typo.monoSmall.copyWith(color: c.ink2)
                        : context.typo.caption.copyWith(color: c.ink2),
                  ),
                ],
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: context.typo.caption.copyWith(
                    color: status == AgentStatus.working
                        ? c.workingText
                        : c.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Project header inside the card: name, folder, summary.
class ProjectHeader extends StatelessWidget {
  const ProjectHeader({super.key, required this.group});
  final HomeGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final summary = projectSummary(group);
    return Semantics(
      header: true,
      label: '${group.label}${summary.isEmpty ? '' : ', $summary'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    group.label,
                    style: context.typo.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      summary,
                      style: context.typo.caption.copyWith(color: c.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ],
            ),
            if (group.path != null) ...[
              const SizedBox(height: 2),
              Text(
                shortPath(group.path!),
                style: context.typo.monoSmall.copyWith(color: c.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = 44});
  final double indent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Divider(height: 1, thickness: 1, color: context.colors.hairline),
  );
}
