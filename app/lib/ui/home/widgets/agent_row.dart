import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

String shortPath(String path) {
  final home = RegExp(r'^/(Users|home)/[^/]+');
  return path.replaceFirst(home, '~');
}

String activityTime(DateTime? at, DateTime now, {bool spoken = false}) {
  if (at == null) return spoken ? 'unknown' : '—';
  final age = now.difference(at);
  if (age.inMinutes < 1) return spoken ? 'less than a minute ago' : 'now';
  if (age.inMinutes < 60) {
    return spoken ? '${age.inMinutes} minutes ago' : '${age.inMinutes}m';
  }
  if (age.inHours < 24) {
    return spoken ? '${age.inHours} hours ago' : '${age.inHours}h';
  }
  if (spoken) return '${age.inDays} days ago';
  return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday -
      1];
}

String shortModel(String model) => model
    .split('/')
    .last
    .replaceFirst(RegExp(r'^claude-'), '')
    .replaceFirst(RegExp(r'-\d{8}$'), '');

class AgentRow extends StatefulWidget {
  const AgentRow({
    super.key,
    required this.item,
    required this.onOpen,
    this.showMachine = false,
    this.selected = false,
    this.highlighted = false,
    this.staleSince,
    this.now,
  });
  final HomeItem item;
  final VoidCallback onOpen;
  final bool showMachine;
  final bool selected;
  final bool highlighted;
  final DateTime? staleSince;
  final DateTime? now;

  @override
  State<AgentRow> createState() => _AgentRowState();
}

class _AgentRowState extends State<AgentRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = context.colors;
    final now = widget.now ?? DateTime.now();
    final status = item.lastKnownStatus;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final statusText = item.stale
        ? 'Last known: ${status.label}'
        : status.label;
    final age = activityTime(item.activity?.lastMessageAt, now);
    final preview = item.activity?.lastMessagePreview?.trim() ?? '';
    final model = item.room.model?.trim() ?? '';
    final isModelId = RegExp(
      r'^[a-z0-9][a-z0-9._:/-]*[0-9][a-z0-9._:/-]*$',
    ).hasMatch(model);
    final path = shortPath(item.room.cwd ?? '—');
    final row = Semantics(
      button: true,
      onTap: widget.onOpen,
      selected: widget.selected,
      label:
          '${item.displayName}, $statusText, ${machineLabel(item.peer)}, last activity ${activityTime(item.activity?.lastMessageAt, now, spoken: true)}',
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            onTap: widget.onOpen,
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: reduceMotion
                    ? 0
                    : _pressed
                    ? 120
                    : 220,
              ),
              curve: _pressed ? Curves.easeOut : Curves.easeInOutCubic,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _pressed || widget.selected || widget.highlighted
                    ? c.surface2
                    : status == AgentStatus.working
                    ? c.workingSoft
                    : c.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    height: 88,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 18,
                          bottom: 0,
                          left: 9,
                          child: SizedBox(
                            width: 1,
                            child: CustomPaint(
                              painter: _PerchRail(
                                c.hairline,
                                item.stale || status == AgentStatus.offline,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.topLeft,
                          child: StatusDot(
                            status: item.status,
                            lastKnownStatus: status,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.displayName,
                                style: context.typo.headline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              age,
                              style: context.typo.caption.copyWith(
                                color: c.ink2,
                                fontFeatures: AppTypography.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (widget.showMachine)
                          MetaChip(label: machineLabel(item.peer))
                        else
                          LayoutBuilder(
                            builder: (context, constraints) => Text(
                              _fittedPath(path, constraints.maxWidth, context),
                              style: context.typo.monoSmall,
                              maxLines: 1,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (model.isNotEmpty)
                              MetaChip(
                                label: isModelId ? shortModel(model) : model,
                                monospace: isModelId,
                              ),
                            if (item.room.thinking != null)
                              MetaChip(
                                label: 'Think ${item.room.thinking!.wire}',
                              ),
                            if (status == AgentStatus.working ||
                                status == AgentStatus.offline)
                              StatusPill(
                                state: status == AgentStatus.working
                                    ? StatusPillState.working
                                    : StatusPillState.offline,
                              )
                            else
                              Text(
                                item.stale
                                    ? 'Last known'
                                    : status == AgentStatus.online
                                    ? 'Idle'
                                    : status.label,
                                style: context.typo.caption.copyWith(
                                  color: c.ink2,
                                ),
                              ),
                          ],
                        ),
                        if (item.stale)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Last known · as of ${activityTime(widget.staleSince, now)}',
                              style: context.typo.caption.copyWith(
                                color: c.ink2,
                              ),
                            ),
                          ),
                        if (MediaQuery.sizeOf(context).width >= 390 &&
                            preview.length >= 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              preview,
                              style: context.typo.subhead.copyWith(
                                color: c.ink2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => CupertinoContextMenu(
        enableHapticFeedback: true,
        actions: [
          CupertinoContextMenuAction(
            trailingIcon: LucideIcons.externalLink,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpen();
            },
            child: const Text('Open'),
          ),
          CupertinoContextMenuAction(
            trailingIcon: LucideIcons.copy,
            onPressed: () {
              Navigator.of(context).pop();
              Clipboard.setData(ClipboardData(text: item.room.cwd ?? ''));
            },
            child: const Text('Copy path'),
          ),
          CupertinoContextMenuAction(
            trailingIcon: LucideIcons.copy,
            onPressed: () {
              Navigator.of(context).pop();
              Clipboard.setData(ClipboardData(text: item.displayName));
            },
            child: const Text('Copy session name'),
          ),
        ],
        // The context-menu preview uses a FittedBox with unbounded child width.
        child: SizedBox(width: constraints.maxWidth, child: row),
      ),
    );
  }
}

String _fittedPath(String value, double width, BuildContext context) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  try {
    for (var length = value.length; length > 0; length--) {
      final candidate = _middleEllipsis(value, length);
      painter.text = TextSpan(text: candidate, style: context.typo.monoSmall);
      painter.layout();
      if (painter.width <= width) return candidate;
    }
    return '…';
  } finally {
    painter.dispose();
  }
}

class _PerchRail extends CustomPainter {
  const _PerchRail(this.color, this.dashed);
  final Color color;
  final bool dashed;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (!dashed) {
      canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
      return;
    }
    for (double y = 0; y < size.height; y += 8) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + 4).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerchRail old) =>
      old.color != color || old.dashed != dashed;
}

String _middleEllipsis(String value, int maxCharacters) {
  if (value.length <= maxCharacters || maxCharacters < 5) return value;
  final left = (maxCharacters - 1) ~/ 2;
  return '${value.substring(0, left)}…${value.substring(value.length - (maxCharacters - left - 1))}';
}
