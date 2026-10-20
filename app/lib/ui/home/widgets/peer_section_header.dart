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
    child: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(label.toUpperCase(), style: context.typo.sectionLabel),
          if (summary.isNotEmpty)
            Text(
              summary,
              style: context.typo.caption.copyWith(color: context.colors.ink2),
              textAlign: TextAlign.end,
            ),
        ],
      ),
    ),
  );
}
