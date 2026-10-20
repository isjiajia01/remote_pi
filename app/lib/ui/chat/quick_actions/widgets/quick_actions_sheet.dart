import 'dart:async';

import 'package:app/data/actions/actions_repository.dart' show ActionFailure;
import 'package:app/protocol/protocol.dart';
import 'package:flutter/cupertino.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/chat/widgets/confirm_chat_action.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/dismiss_on_session_change.dart';
import 'package:app/ui/chat/quick_actions/widgets/model_picker_sheet.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

/// Plan/28 Wave C — entry point for the Quick Actions sheet from the
/// navigation menu. Reuses the route-scoped [QuickActionsViewModel] so the
/// context strip reflects pending changes and surfaces inline failures.
///
/// Both the messenger and the `session_new` reset callback are captured
/// from the *page* context here, before the sheet pushes its own route —
/// the modal's builder context lives above the chat page's providers, so
/// `context.read<ChatViewModel>()` inside the sheet would not resolve.
Future<void> showQuickActionsSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final chat = context.read<ChatViewModel>();
  // Captured to auto-close the sheet if the tablet's selected session changes
  // out from under it (the sheet lives on the detail-pane navigator).
  final selection = context.read<SessionSelection>();
  final actions = context.read<QuickActionsViewModel>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.bg,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return DismissOnSessionChange(
        selection: selection,
        child: ChangeNotifierProvider<QuickActionsViewModel>.value(
          value: actions,
          child: QuickActionsSheetBody(
            messenger: messenger,
            onSessionReset: chat.clearActiveSession,
            inlineErrors: true,
          ),
        ),
      );
    },
  );
}

/// Body of the Quick Actions sheet. Public so widget tests can drive the
/// real action handlers (close-on-success, toasts, session reset) with a
/// fake ViewModel instead of the replica harness they used before.
class QuickActionsSheetBody extends StatefulWidget {
  final ScaffoldMessengerState messenger;

  /// Invoked after the Pi acks a `session_new`, to wipe the local chat
  /// mirror. Optional so tests can omit it; in the app it is wired to
  /// [ChatViewModel.clearActiveSession].
  final Future<void> Function()? onSessionReset;
  final bool inlineErrors;

  const QuickActionsSheetBody({
    super.key,
    required this.messenger,
    this.onSessionReset,
    this.inlineErrors = false,
  });

  @override
  State<QuickActionsSheetBody> createState() => _QuickActionsSheetBodyState();
}

class _QuickActionsSheetBodyState extends State<QuickActionsSheetBody> {
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Listener is attached in didChangeDependencies so we have a vm.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<QuickActionsViewModel>();
      if (!widget.inlineErrors) _errorSub = vm.errors.listen(_showError);
    });
  }

  void _showError(String message) =>
      _toast(message, widget.messenger.context.colors.error);

  /// Toasts go through the chat scaffold's messenger (captured before the
  /// sheet opened) so success/failure feedback survives the sheet being
  /// popped on success.
  void _toast(String message, Color color) {
    final colors = widget.messenger.context.colors;
    widget.messenger.showSnackBar(
      SnackBar(
        backgroundColor: colors.surface,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: widget.messenger.context.typo.footnote.copyWith(color: color),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuickActionsViewModel>();
    final state = vm.state;
    final busyAction = state is QuickActionsBusy ? state.action : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _DragHandle(),
            const SizedBox(height: 6),
            const _SheetTitle(text: 'Quick actions'),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-compact'),
              icon: LucideIcons.shrink,
              label: 'Compact context',
              subtitle: 'Summarize old turns to free room.',
              busy: busyAction == ActionName.sessionCompact,
              onTap: busyAction != null ? null : () => _onCompact(vm),
            ),
            const _Divider(),
            _ActionTile(
              key: const Key('qa-new-session'),
              icon: LucideIcons.sparkles,
              label: 'New session',
              subtitle: 'Starts a fresh conversation.',
              busy: busyAction == ActionName.sessionNew,
              onTap: busyAction != null ? null : () => _onNewSession(vm),
            ),
            const _Divider(),
            _ModelRow(
              currentLabel: vm.currentModel?.name ?? vm.currentModelName,
              busy: busyAction == ActionName.modelSet,
              onTap: busyAction != null ? null : () => _openModelPicker(vm),
            ),
            const _Divider(),
            _ThinkingRow(
              current: vm.currentThinking,
              busy: busyAction == ActionName.thinkingSet,
              disabled: busyAction != null,
              onPick: (level) => _onThinking(vm, level),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _onCompact(QuickActionsViewModel vm) async {
    final confirm = await confirmChatAction(context, newSession: false);
    if (!confirm || !mounted) return;
    try {
      await vm.compact();
    } catch (_) {
      // Failure already surfaced as an error toast via `vm.errors`; leave
      // the sheet open so the user can retry.
      return;
    }
    // action_ok — just close the sheet (no success toast: compacting is a
    // quiet, frequent action and the toast was noise).
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onNewSession(QuickActionsViewModel vm) async {
    // Close the sheet up front — the confirm dialog stands on its own. We
    // capture the root navigator BEFORE popping (our own context dies with
    // the sheet) so the dialog is shown on the root, same as before. Toasts
    // use `widget.messenger`, which outlives the sheet.
    final selection = context.read<SessionSelection?>();
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    final confirm = await confirmChatAction(
      rootNavigator.context,
      newSession: true,
      sessionSelection: selection,
    );
    if (confirm != true) return;
    try {
      await vm.newSession();
    } on ActionFailure catch (e) {
      // The sheet is already closed, so its `vm.errors` listener is gone —
      // surface the failure toast directly through the captured messenger.
      if (!widget.inlineErrors) _showError(e.message);
      return;
    } catch (_) {
      return;
    }
    // action_ok — wipe the local chat mirror so the UI reflects the fresh
    // session. The sheet is already closed; no success toast (quiet action,
    // the cleared chat is feedback enough).
    await widget.onSessionReset?.call();
  }

  Future<void> _onThinking(
    QuickActionsViewModel vm,
    ThinkingLevel level,
  ) async {
    try {
      await vm.setThinking(level);
    } catch (_) {
      /* surfaced via vm.errors */
    }
  }

  Future<void> _openModelPicker(QuickActionsViewModel vm) async {
    await showModelPickerSheet(context, vm: vm);
  }
}

// ---------------------------------------------------------------------------
// UI pieces
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: context.colors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.muted,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: context.colors.border, height: 1, thickness: 1);
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: colors.accent, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: colors.muted),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  /// Display label — `WireModel.name` when the catalogue is loaded,
  /// otherwise the `room_meta.model` string. `null` falls back to the
  /// generic placeholder. Reads cheap so the picker can lazy-load.
  final String? currentLabel;
  final bool busy;
  final VoidCallback? onTap;
  const _ModelRow({
    required this.currentLabel,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = currentLabel ?? (busy ? 'Switching…' : 'Choose a model');
    return InkWell(
      key: const Key('qa-model-row'),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(LucideIcons.memoryStick, color: colors.accent, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model',
                    style: TextStyle(fontSize: 11, color: colors.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colors.accent,
                ),
              )
            else
              Icon(LucideIcons.chevronRight, color: colors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  final ThinkingLevel? current;
  final bool busy;
  final bool disabled;
  final ValueChanged<ThinkingLevel> onPick;
  const _ThinkingRow({
    required this.current,
    required this.busy,
    required this.disabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.brain, color: colors.accent, size: 18),
              const SizedBox(width: 14),
              Text(
                'Thinking',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
              const Spacer(),
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ThinkingSegmented(
            current: current,
            disabled: disabled,
            onPick: onPick,
          ),
        ],
      ),
    );
  }
}

class ThinkingSegmented extends StatelessWidget {
  final ThinkingLevel? current;
  final bool disabled;
  final ValueChanged<ThinkingLevel> onPick;
  const ThinkingSegmented({
    super.key,
    required this.current,
    required this.disabled,
    required this.onPick,
  });

  // Short label shown in the segmented buttons. Matches the SDK's
  // ThinkingLevel order (off → xhigh).
  static const _labels = <ThinkingLevel, String>{
    ThinkingLevel.off: 'off',
    ThinkingLevel.minimal: 'min',
    ThinkingLevel.low: 'low',
    ThinkingLevel.medium: 'med',
    ThinkingLevel.high: 'high',
    ThinkingLevel.xhigh: 'x',
  };

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: disabled,
      child: Opacity(
        opacity: disabled ? .4 : 1,
        child: CupertinoSlidingSegmentedControl<ThinkingLevel>(
          groupValue: current,
          backgroundColor: context.colors.surface2,
          thumbColor: context.colors.surface,
          children: {
            for (final level in ThinkingLevel.values)
              level: Padding(
                key: Key('qa-thinking-${level.wire}'),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(_labels[level]!, style: context.typo.footnote),
              ),
          },
          onValueChanged: (value) {
            if (value != null && !disabled) onPick(value);
          },
        ),
      ),
    );
  }
}
