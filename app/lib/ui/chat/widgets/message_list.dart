import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'message_bubble.dart';
import 'streaming_bubble.dart';
import 'tool_request_card.dart';

class ChatMessageList extends StatefulWidget {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final List<String> answeredQuestions;
  final ValueChanged<UserMsg>? onRetry;
  final void Function(String, ApproveDecision) onDecide;
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.streaming,
    required this.onDecide,
    required this.onRetry,
    required this.answeredQuestions,
  });
  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final _scroll = ScrollController();
  bool _newOutput = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scroll.offset <= 120 && _newOutput) setState(() => _newOutput = false);
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.messages != widget.messages ||
        oldWidget.streaming != widget.streaming ||
        !listEquals(oldWidget.answeredQuestions, widget.answeredQuestions);
    if (!changed || !_scroll.hasClients) return;
    if (_scroll.offset <= 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    } else {
      _newOutput = true;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turns = <Widget>[];
    for (var i = 0; i < widget.messages.length; i++) {
      final msg = widget.messages[i];
      if (msg is ToolEvent) {
        final tools = <ToolEvent>[msg];
        while (i + 1 < widget.messages.length &&
            widget.messages[i + 1] is ToolEvent) {
          tools.add(widget.messages[++i] as ToolEvent);
        }
        turns.add(
          ToolCallGroup(
            key: ValueKey('tools-${msg.id}'),
            tools: tools,
            onDecide: widget.onDecide,
          ),
        );
      } else {
        turns.add(
          KeyedSubtree(
            key: ValueKey(msg.id),
            child: switch (msg) {
              UserMsg() => UserBubble(
                msg,
                onRetry: widget.onRetry == null
                    ? null
                    : () => widget.onRetry!(msg),
              ),
              AssistantMsg() => AssistantBubble(msg),
              CompactionMsg() => CompactionBubble(msg),
              ToolEvent() => throw StateError('Tools are grouped above'),
            },
          ),
        );
      }
    }
    for (var i = 0; i < widget.answeredQuestions.length; i++) {
      turns.add(
        Text(
          'Answered: ${widget.answeredQuestions[i]}',
          key: ValueKey('answer-$i'),
          style: context.typo.caption.copyWith(color: context.colors.ink2),
        ),
      );
    }
    if (widget.streaming != null) {
      turns.add(
        StreamingBubble(widget.streaming!, key: const ValueKey('streaming')),
      );
    }
    return Stack(
      children: [
        ListView.separated(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.all(16),
          itemCount: turns.length,
          // Preserve expanded tool/streaming state when reverse indices shift.
          // ignore: deprecated_member_use
          findChildIndexCallback: (key) {
            final index = turns.indexWhere((turn) => turn.key == key);
            return index < 0 ? null : (turns.length - 1 - index) * 2;
          },
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => turns[turns.length - 1 - i],
        ),
        if (_newOutput)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: context.colors.surface,
                  foregroundColor: context.colors.ink,
                  minimumSize: const Size(0, 32),
                  side: BorderSide(color: context.colors.hairline),
                  textStyle: context.typo.caption,
                ),
                onPressed: () {
                  _scroll.jumpTo(0);
                  setState(() => _newOutput = false);
                },
                child: const Text('↓ New output'),
              ),
            ),
          ),
      ],
    );
  }
}
