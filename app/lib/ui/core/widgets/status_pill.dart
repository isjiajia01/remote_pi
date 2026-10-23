import 'package:flutter/widgets.dart';
import 'package:app/ui/core/themes/themes.dart';

enum StatusPillState { working, offline, error }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state});

  final StatusPillState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, background, foreground) = switch (state) {
      StatusPillState.working => ('Working', c.workingSoft, c.workingText),
      StatusPillState.offline => ('Offline', c.surface2, c.ink2),
      StatusPillState.error => ('Error', c.errorSoft, c.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: context.typo.caption.copyWith(color: foreground),
      ),
    );
  }
}
