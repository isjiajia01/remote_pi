import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/agent_markdown.dart';
import 'package:app/ui/chat/widgets/image_bubble.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ---------------------------------------------------------------------------
// UserBubble — right-aligned dark card
// ---------------------------------------------------------------------------

class UserBubble extends StatelessWidget {
  final UserMsg message;
  final VoidCallback? onRetry;
  const UserBubble(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Plan/24-fix-app-source-of-truth: render the lifecycle stage of
    // the bubble. `pending` (sent over WS, Pi hasn't echoed yet) gets
    // reduced opacity + a small spinner; `failed` (no echo in 15s) gets
    // a red exclamation badge so the user knows to retry.
    final isPending = message.status == UserMsgStatus.pending;
    final isFailed = message.status == UserMsgStatus.failed;
    final isSteering = message.steering;
    // Plan/30 — when an image is attached the bubble becomes an ImageBubble
    // (thumbnail + caption); otherwise the existing text card.
    final image = message.image;
    final colors = context.colors;
    final typo = context.typo;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * .8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Opacity(
                opacity: isPending ? 0.6 : 1.0,
                child: image != null
                    ? ImageBubble(
                        image: image,
                        caption: message.text,
                        isFailed: isFailed,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: colors.userBubble,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14),
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(6),
                          ),
                          border: isFailed
                              ? Border.all(color: colors.error, width: 1)
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        // Selectable so the user can copy their own message (the
                        // agent reply is already selectable via AgentMarkdown).
                        child: SelectableText(
                          message.text,
                          style: typo.chatBody.copyWith(color: colors.text),
                        ),
                      ),
              ),
              if (isPending || isSteering || isFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isFailed && (isPending || isSteering)) ...[
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            color: colors.muted,
                            strokeWidth: 1.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSteering ? 'steering…' : 'sending…',
                          style: typo.caption.copyWith(color: colors.ink2),
                        ),
                      ] else ...[
                        Icon(
                          LucideIcons.circleAlert,
                          size: 12,
                          color: colors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Not sent',
                          style: typo.caption.copyWith(color: colors.error),
                        ),
                        if (onRetry != null)
                          TextButton(
                            onPressed: onRetry,
                            child: const Text('Retry'),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CompactionBubble — centered system card (plan/32)
// ---------------------------------------------------------------------------

/// A system message distinct from user/assistant: shows that the Pi compacted
/// the context, with the recap summary and the reclaimed token count. Mirrors
/// the TUI's CompactionSummaryMessageComponent.
class CompactionBubble extends StatelessWidget {
  final CompactionMsg message;
  const CompactionBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final time = message.timestamp?.toLocal();
    final label = time == null
        ? 'Context compacted'
        : 'Context compacted · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: colors.hairline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: context.typo.caption.copyWith(color: colors.ink2),
              ),
            ),
            Expanded(child: Divider(color: colors.hairline)),
          ],
        ),
        // Retain the recap and token details without making the marker a turn.
        if (message.summary.isNotEmpty || message.tokensBefore != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'Details',
              style: context.typo.caption.copyWith(color: colors.ink2),
            ),
            children: [
              if (message.tokensBefore != null)
                Text(
                  '~${message.tokensBefore} tokens',
                  style: context.typo.caption.copyWith(color: colors.ink2),
                ),
              if (message.summary.isNotEmpty)
                Text(
                  message.summary,
                  style: context.typo.footnote.copyWith(color: colors.ink2),
                ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AssistantBubble — left-aligned monospace text
// ---------------------------------------------------------------------------

class AssistantBubble extends StatelessWidget {
  final AssistantMsg message;
  const AssistantBubble(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    // Plan/32b — agent output is rendered as Markdown (GFM + code blocks),
    // spanning the FULL content width (the message list already pads 16px on
    // each side) — unlike the user's right-aligned chat bubble, which stays
    // capped. Selectable so prose/code can be copied.
    return SizedBox(
      width: double.infinity,
      child: AgentMarkdown(message.text, selectable: true),
    );
  }
}
