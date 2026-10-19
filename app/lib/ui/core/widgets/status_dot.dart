import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:app/ui/core/themes/themes.dart';

enum AgentStatus { working, online, offline, checking, unknown, stale }

extension AgentStatusLabel on AgentStatus {
  String get label => switch (this) {
    AgentStatus.working => 'Working',
    AgentStatus.online => 'Online',
    AgentStatus.offline => 'Offline',
    AgentStatus.checking || AgentStatus.unknown => 'Checking',
    AgentStatus.stale => 'Last known',
  };
}

/// Pair with visible status text in rows; the dot also labels itself for AT.
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.status,
    this.lastKnownStatus = AgentStatus.working,
    this.size = 10,
  }) : assert(lastKnownStatus != AgentStatus.stale);

  final AgentStatus status;
  final AgentStatus lastKnownStatus;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  void _updatePulse() {
    if (widget.status == AgentStatus.working &&
        !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePulse();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final working = widget.status == AgentStatus.working;
    final filled = working || widget.status == AgentStatus.online;
    final checking =
        widget.status == AgentStatus.checking ||
        widget.status == AgentStatus.unknown;
    final color = working
        ? colors.working
        : filled
        ? colors.online
        : colors.ink3;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.status == AgentStatus.stale
          ? 'Last known: ${widget.lastKnownStatus.label}'
          : widget.status.label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = Curves.easeInOut.transform(_pulse.value);
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (working && !reduceMotion)
                    Container(
                      width: widget.size + (20 - widget.size) * t,
                      height: widget.size + (20 - widget.size) * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: .35 * (1 - t)),
                      ),
                    ),
                  Transform.scale(
                    scale: working && !reduceMotion ? 1 + .35 * t : 1,
                    child: Opacity(
                      opacity: checking ? .5 : 1,
                      child: widget.status == AgentStatus.stale
                          ? CustomPaint(
                              size: Size.square(widget.size),
                              painter: _DashedRing(color),
                            )
                          : AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOut,
                              width: widget.size,
                              height: widget.size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled ? color : null,
                                border: filled
                                    ? null
                                    : Border.all(color: color, width: 1.5),
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DashedRing extends CustomPainter {
  const _DashedRing(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(.75);
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(rect, i * math.pi / 3, math.pi / 5, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing oldDelegate) => color != oldDelegate.color;
}
