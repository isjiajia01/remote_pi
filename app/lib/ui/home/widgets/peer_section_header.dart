import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:flutter/widgets.dart';

class PeerSectionHeader extends StatelessWidget {
  const PeerSectionHeader({super.key, required this.peer, this.summary = ''});
  final PeerRecord peer;
  final String summary;
  @override
  Widget build(BuildContext context) =>
      AgentSectionHeader(label: machineLabel(peer), summary: summary);
}

class AgentSectionHeader extends StatelessWidget {
  const AgentSectionHeader({super.key, required this.label, this.summary = ''});
  final String label;
  final String summary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: context.typo.sectionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              summary,
              style: context.typo.caption.copyWith(color: context.colors.ink2),
              maxLines: 2,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ],
    ),
  );
}
