import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Informational only: approval controls remain hidden; the API is retained.
class ToolRequestCard extends StatefulWidget {
  final ToolEvent tool;
  final void Function(String toolCallId, ApproveDecision decision)? onDecide;
  const ToolRequestCard({super.key, required this.tool, this.onDecide});

  @override
  State<ToolRequestCard> createState() => _ToolRequestCardState();
}

class _ToolRequestCardState extends State<ToolRequestCard> {
  late bool _expanded = widget.tool.status == ToolEventStatus.failed;
  bool _showAll = false;
  ToolEvent get tool => widget.tool;
  bool get _running =>
      tool.status == ToolEventStatus.pending ||
      tool.status == ToolEventStatus.allowed;

  @override
  void didUpdateWidget(ToolRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool.id != tool.id) {
      _expanded = tool.status == ToolEventStatus.failed;
      _showAll = false;
    } else if (oldWidget.tool.status != ToolEventStatus.failed &&
        tool.status == ToolEventStatus.failed) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = switch (tool.status) {
      ToolEventStatus.pending || ToolEventStatus.allowed => 'Running',
      ToolEventStatus.completed => 'Done',
      ToolEventStatus.failed => 'Failed',
      ToolEventStatus.denied => 'Denied',
      ToolEventStatus.expired => 'Expired',
    };
    final statusColor = switch (tool.status) {
      ToolEventStatus.pending || ToolEventStatus.allowed => c.accent,
      ToolEventStatus.completed => c.online,
      ToolEventStatus.failed => c.error,
      ToolEventStatus.denied || ToolEventStatus.expired => c.ink3,
    };
    final output = tool.result?.toString() ?? '';
    final lines = output.split('\n');
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _running ? c.accent : c.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: '${tool.tool}, $status',
            child: InkWell(
              key: ValueKey('tool-toggle-${tool.id}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      if (_running)
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: c.accent,
                          ),
                        )
                      else
                        Icon(
                          tool.status == ToolEventStatus.completed
                              ? LucideIcons.check
                              : tool.status == ToolEventStatus.failed
                              ? LucideIcons.x
                              : LucideIcons.minus,
                          size: 16,
                          color: statusColor,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        tool.tool,
                        style: context.typo.mono.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatArgs(tool.tool, tool.args),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.monoSmall,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 16,
                        color: c.ink3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Duration(
              milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250,
            ),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildToolSummary(context),
                        if (output.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _showAll ? output : lines.take(12).join('\n'),
                            style: context.typo.monoCode,
                          ),
                          if (lines.length > 12 && !_showAll)
                            TextButton(
                              onPressed: () => setState(() => _showAll = true),
                              child: const Text('Show all'),
                            ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          tool.error ?? status,
                          style: context.typo.caption.copyWith(
                            color: tool.status == ToolEventStatus.failed
                                ? c.error
                                : c.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSummary(BuildContext context) {
    final display = _formatToolDisplay(tool.tool, tool.args);
    if (display == null) {
      return SelectableText(
        _formatArgs(tool.tool, tool.args),
        style: context.typo.monoCode,
      );
    }
    return Text.rich(
      TextSpan(
        style: context.typo.monoCode,
        children: [
          TextSpan(text: display.command),
          for (final line in display.lines) ...[
            const TextSpan(text: '\n'),
            TextSpan(
              text: line.text,
              style: TextStyle(color: line.color(context.colors)),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatArgs(String tool, dynamic args) {
    if (args == null) return '';
    final normalizedTool = tool.toLowerCase();
    if (args is Map) {
      return switch (normalizedTool) {
        'bash' => (args['command'] as String?) ?? '',
        'edit' || 'write' =>
          '$normalizedTool ${_stringArg(args, const ['file_path', 'path'])}',
        _ => args.entries.map((e) => '${e.key}=${e.value}').join(' '),
      };
    }
    return args.toString();
  }

  static _ToolDisplay? _formatToolDisplay(String tool, dynamic args) {
    if (args is! Map) return null;
    return switch (tool.toLowerCase()) {
      'edit' => _formatEditDisplay(args),
      _ => null,
    };
  }

  static _ToolDisplay? _formatEditDisplay(Map args) {
    final filePath = _stringArg(args, const ['file_path', 'path']);
    final lines = <_DiffLine>[];
    final hunks = args['hunks'];
    if (hunks is! Iterable) return null;

    for (final hunk in hunks) {
      if (hunk is! Map || hunk['lines'] is! Iterable) continue;
      if (lines.isNotEmpty) lines.add(_DiffLine.context('      ...'));
      for (final rawLine in hunk['lines'] as Iterable) {
        if (rawLine is! Map) continue;
        final text = _lineText(rawLine);
        switch (rawLine['kind']) {
          case 'context':
            lines.add(_DiffLine.context(text));
          case 'remove':
            lines.add(_DiffLine.removed(text));
          case 'add':
            lines.add(_DiffLine.added(text));
          case 'ellipsis':
            lines.add(_DiffLine.context('      ...'));
        }
      }
    }

    if (lines.isEmpty) return null;
    return _ToolDisplay(command: 'edit $filePath', lines: lines);
  }

  static String _lineText(Map rawLine) {
    final sign = switch (rawLine['kind']) {
      'remove' => '-',
      'add' => '+',
      _ => ' ',
    };
    final lineNumber = rawLine['oldLine'] ?? rawLine['newLine'];
    final number = lineNumber is int ? lineNumber.toString().padLeft(3) : '   ';
    return '$sign $number ${rawLine['text'] ?? ''}';
  }

  static String _stringArg(Map args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value is String) return value;
    }
    return '';
  }
}

class _ToolDisplay {
  final String command;
  final List<_DiffLine> lines;

  const _ToolDisplay({required this.command, required this.lines});
}

class _DiffLine {
  final String text;
  final Color Function(AppColors colors) color;

  const _DiffLine._(this.text, this.color);

  factory _DiffLine.removed(String text) =>
      _DiffLine._(text, (colors) => colors.error);

  factory _DiffLine.added(String text) =>
      _DiffLine._(text, (colors) => colors.success);

  factory _DiffLine.context(String text) =>
      _DiffLine._(text, (colors) => colors.text);
}

/// Consecutive tools form one group; failures remain visible immediately.
class ToolCallGroup extends StatefulWidget {
  const ToolCallGroup({super.key, required this.tools, this.onDecide});
  final List<ToolEvent> tools;
  final void Function(String, ApproveDecision)? onDecide;
  @override
  State<ToolCallGroup> createState() => _ToolCallGroupState();
}

class _ToolCallGroupState extends State<ToolCallGroup> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final hasFailure = widget.tools.any(
      (t) => t.status == ToolEventStatus.failed,
    );
    final grouped = widget.tools.length > 3;
    final show = !grouped || _expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grouped)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text(
                  '${widget.tools.length} tool calls',
                  style: context.typo.caption.copyWith(
                    color: context.colors.ink2,
                  ),
                ),
                const Spacer(),
                Icon(
                  show ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: context.colors.ink3,
                ),
              ],
            ),
          ),
        if (!show && hasFailure)
          for (final tool in widget.tools.where(
            (t) => t.status == ToolEventStatus.failed,
          ))
            ToolRequestCard(
              key: ValueKey(tool.id),
              tool: tool,
              onDecide: widget.onDecide,
            ),
        if (show)
          for (var i = 0; i < widget.tools.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            ToolRequestCard(
              key: ValueKey(widget.tools[i].id),
              tool: widget.tools[i],
              onDecide: widget.onDecide,
            ),
          ],
      ],
    );
  }
}
