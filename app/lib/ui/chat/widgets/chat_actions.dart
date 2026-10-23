import 'dart:async';

import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/dismiss_on_session_change.dart';
import 'package:app/ui/chat/quick_actions/widgets/model_picker_sheet.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'confirm_chat_action.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class ChatMenu extends StatelessWidget {
  const ChatMenu({super.key, required this.enabled, required this.onInfo});
  final bool enabled;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final actions = context.watch<QuickActionsViewModel?>();
    final busy = actions?.state is QuickActionsBusy;
    return PopupMenuButton<String>(
      tooltip: 'Session menu',
      icon: Icon(LucideIcons.ellipsis, size: 22, color: context.colors.ink2),
      color: context.colors.surface,
      onSelected: (action) async {
        if (action == 'info') {
          onInfo();
        } else if (action == 'quick') {
          await showQuickActionsSheet(context);
        } else if (actions != null) {
          final chat = context.read<ChatViewModel>();
          final confirmed = await confirmChatAction(
            context,
            newSession: action == 'new',
          );
          if (!confirmed || !context.mounted) return;
          try {
            if (action == 'new') {
              await actions.newSession();
              if (context.mounted) await chat.clearActiveSession();
            } else {
              await actions.compact();
            }
          } catch (_) {
            // Context strip owns the inline failure banner.
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'quick',
          enabled: enabled && !busy,
          child: const Text('Quick actions…'),
        ),
        PopupMenuItem(
          value: 'compact',
          enabled: enabled && !busy,
          child: const Text('Compact context'),
        ),
        PopupMenuItem(
          value: 'new',
          enabled: enabled && !busy,
          child: const Text('New session'),
        ),
        const PopupMenuItem(value: 'info', child: Text('Session info')),
      ],
    );
  }
}

/// Sticky metadata and the shared action error feed survive picker dismissal.
class ChatContextStrip extends StatefulWidget {
  const ChatContextStrip({
    super.key,
    required this.enabled,
    this.cwd,
    this.working = false,
    this.model,
    this.thinking,
  });
  final bool enabled;
  final String? cwd;
  final bool working;
  final String? model;
  final ThinkingLevel? thinking;
  @override
  State<ChatContextStrip> createState() => _ChatContextStripState();
}

class _ChatContextStripState extends State<ChatContextStrip> {
  final _workingWatch = Stopwatch();
  Timer? _workingTimer;

  void _syncWorking() {
    if (widget.working) {
      if (!_workingWatch.isRunning) {
        _workingWatch.reset();
        _workingWatch.start();
      }
      _workingTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _workingTimer?.cancel();
      _workingTimer = null;
      _workingWatch.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncWorking();
  }

  @override
  void didUpdateWidget(ChatContextStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWorking();
  }

  QuickActionsViewModel? _vm;
  StreamSubscription<String>? _errors;
  Timer? _dismiss;
  String? _error;
  ActionName? _lastAction;

  void _trackAction() {
    final state = _vm?.state;
    if (state is QuickActionsBusy) _lastAction = state.action;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<QuickActionsViewModel?>();
    if (identical(vm, _vm)) return;
    _errors?.cancel();
    _vm?.removeListener(_trackAction);
    _vm = vm;
    _vm?.addListener(_trackAction);
    _errors = vm?.errors.listen((reason) {
      if (!mounted) return;
      final subject = switch (_lastAction) {
        ActionName.modelSet => 'change model',
        ActionName.thinkingSet => 'change thinking',
        ActionName.sessionCompact => 'compact context',
        ActionName.sessionNew => 'start a new session',
        _ => 'complete action',
      };
      setState(() => _error = "Couldn't $subject — $reason");
      _dismiss?.cancel();
      _dismiss = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _error = null);
      });
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    _vm?.removeListener(_trackAction);
    _workingTimer?.cancel();
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuickActionsViewModel?>();
    final state = vm?.state;
    final busy = state is QuickActionsBusy;
    if (state is QuickActionsBusy) _lastAction = state.action;
    final enabled = widget.enabled && !busy && vm != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.hairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: enabled
                  ? () => showModelPickerSheet(context, vm: vm)
                  : null,
              child: Row(
                children: [
                  if (busy) ...[
                    const CupertinoActivityIndicator(radius: 8),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      state?.currentModelName ?? widget.model ?? 'Model',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.footnote,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Think ${(state?.currentThinking ?? widget.thinking)?.wire ?? '—'}',
                    style: context.typo.caption.copyWith(
                      color: context.colors.ink2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.chevronDown, size: 16),
                  if (widget.working) ...[
                    const SizedBox(width: 12),
                    Text(
                      '${_workingWatch.elapsed.inMinutes}:${(_workingWatch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: context.typo.caption.copyWith(
                        color: context.colors.workingText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppBanner(message: _error!, variant: BannerVariant.error),
          ),
      ],
    );
  }
}

Future<void> showThinkingPickerSheet(
  BuildContext context, {
  required QuickActionsViewModel vm,
}) {
  final selection = context.read<SessionSelection>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    builder: (_) => DismissOnSessionChange(
      selection: selection,
      child: ChangeNotifierProvider.value(
        value: vm,
        child: const ThinkingPickerBody(),
      ),
    ),
  );
}

class ThinkingPickerBody extends StatelessWidget {
  const ThinkingPickerBody({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QuickActionsViewModel>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Thinking', style: context.typo.title2),
            const SizedBox(height: 16),
            ThinkingSegmented(
              current: vm.currentThinking,
              disabled: vm.state is QuickActionsBusy,
              onPick: (level) async {
                try {
                  await vm.setThinking(level);
                  if (context.mounted) Navigator.of(context).pop();
                } catch (_) {
                  /* inline error feed */
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
