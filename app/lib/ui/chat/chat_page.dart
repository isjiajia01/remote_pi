import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'dart:async';
import 'package:app/ui/chat/widgets/perch_approval_card.dart';

import 'package:app/ui/chat/widgets/chat_actions.dart';
import 'package:app/ui/chat/widgets/chat_status_banner.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:app/ui/chat/attachment/states/attachment_state.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/chat/widgets/attach_sheet.dart';
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:app/ui/chat/widgets/message_list.dart';
import 'package:app/ui/chat/widgets/extension_ui_sheet.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class ChatPage extends StatefulWidget {
  /// Plan/24-fix-title: optional title hint passed via `go_router`
  /// `extra` from the Home tile. Used as the peer-label fallback in
  /// the AppBar so the user sees the right name *immediately* on
  /// navigation, instead of "—" / "Remote Pi" until the PeerRecord
  /// is loaded by the ViewModel and the first `room_meta_updated`
  /// arrives.
  final String? initialTitle;

  /// Plan/32g — the paired-device (Mac) label Home already knows, passed via
  /// `extra` / [SessionSelection]. Drives the AppBar's line 2 immediately so
  /// it never flickers empty/room-title while the PeerRecord loads async.
  /// When the PeerRecord arrives it resolves to the same string, so there's no
  /// visible change.
  final String? initialDevice;

  /// Plan/32g — the live state of the tile Home tapped (its green dot). Seeds
  /// the AppBar status dot so it doesn't flash "reconnecting" before the VM
  /// reads the real runtime. Superseded by the live signal once it resolves
  /// ([ChatViewModel.connectionResolved]).
  final bool initialOnline;

  /// Plan/tablet — `false` when the chat is embedded as the tablet's
  /// detail pane (no navigation stack to pop back to). Hides the back
  /// arrow; defaults to `true` for the phone full-screen route.
  final bool showBack;

  const ChatPage({
    super.key,
    this.initialTitle,
    this.initialDevice,
    this.initialOnline = false,
    this.showBack = true,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  bool _stopRequested = false;
  String? _voiceHint;
  bool _voicePermission = false;
  Timer? _voiceDismiss;

  @override
  void dispose() {
    _voiceDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final state = vm.state;

    final scaffold = Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context, state),
            if (state is! ChatFatalError && state is! ChatNoPeer)
              ChatContextStrip(
                enabled: state is ChatReady && !state.readOnly,
                cwd: vm.activeRoom?.cwd,
                working: vm.isWorking,
                model: vm.activeRoom?.model,
                thinking: vm.activeRoom?.thinking,
              ),
            ChatStatusBanner(
              state: state,
              machine: _peerDisplayName(vm.activePeer, widget.initialDevice),
              onReconnect: vm.reconnect,
              onPairAgain: () => context.go('/pair'),
            ),
            if (_voiceHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppBanner(
                  message: _voiceHint!,
                  actionLabel: _voicePermission ? 'Open Settings' : null,
                  onAction: _voicePermission
                      ? AppSettings.openAppSettings
                      : null,
                ),
              ),
            if (vm.approvals.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final approval in vm.approvals)
                        PerchApprovalCard(
                          key: ValueKey(approval.request.id),
                          approval: approval,
                          enabled: state is ChatReady && !state.readOnly,
                          onDecide: (decision) =>
                              vm.decideApproval(approval, decision),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(child: _buildBody(context, state, vm)),
            if (_stopRequested && !vm.isWorking)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'You stopped this response',
                    style: context.typo.caption.copyWith(
                      color: context.colors.ink2,
                    ),
                  ),
                ),
              ),
            SafeArea(top: false, child: _buildInput(context, state, vm)),
          ],
        ),
      ),
    );

    // Plan/57 — an interactive extension_ui_request (ask_user via pi-ask)
    // renders as a full-screen modal layered ABOVE the Scaffold. Purely
    // reactive: the overlay leaves the tree when the pending request clears
    // (completed dismiss) — no route lifecycle to manage. `error` carries a
    // submit-result rejection so the modal can offer a retry instead of a dead
    // end.
    final ready = state is ChatReady ? state : null;
    final uiRequest = ready?.pendingUiRequest;
    if (uiRequest == null) return scaffold;
    return Stack(
      children: [
        scaffold,
        Positioned.fill(
          // Keyed by request id: a new flow must get a fresh State — question
          // ids repeat across flows (e.g. "goal"), so reusing the State would
          // leak old selections/custom text into the new modal.
          child: ExtensionUiSheet(
            key: ValueKey(uiRequest.id),
            request: uiRequest,
            error: ready?.pendingUiError,
            onRespond: vm.respondExtensionUi,
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, ChatState state) {
    final vm = context.watch<ChatViewModel>();
    final isOnline = vm.connectionResolved
        ? vm.isRoomLive
        : widget.initialOnline;
    final status = state is ChatReady && state.isOffline
        ? AgentStatus.stale
        : vm.isWorking && isOnline
        ? AgentStatus.working
        : isOnline
        ? AgentStatus.online
        : !vm.connectionResolved || state is ChatConnecting
        ? AgentStatus.checking
        : AgentStatus.offline;
    final roomName = _roomDisplayName(
      vm.activeRoom,
      state,
      widget.initialTitle,
    );
    final peerLabel = _peerDisplayName(vm.activePeer, widget.initialDevice);
    return CupertinoNavigationBar(
      backgroundColor: context.colors.bg,
      border: Border(bottom: BorderSide(color: context.colors.hairline)),
      automaticallyImplyLeading: false,
      leading: widget.showBack
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
              child: Icon(
                LucideIcons.chevronLeft,
                size: 22,
                color: context.colors.accent,
              ),
            )
          : null,
      middle: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            roomName,
            style: context.typo.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(
                status: status,
                lastKnownStatus: vm.isWorking
                    ? AgentStatus.working
                    : AgentStatus.online,
                size: 8,
              ),
              Text(
                '${status.label} · ',
                style: context.typo.caption.copyWith(
                  color: context.colors.ink2,
                ),
              ),
              Flexible(
                child: Text(
                  peerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.caption.copyWith(
                    color: context.colors.ink2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: ChatMenu(
        enabled: state is ChatReady && !state.readOnly,
        onInfo: () {
          final peer = vm.activePeer;
          if (peer != null) {
            _showSessionInfo(context, peer, vm.activeRoom, roomName);
          }
        },
      ),
    );
  }

  /// Session details dialog — surfaced from the AppBar info action.
  /// Shows the human name, the Pi-side path (cwd), the owning device,
  /// plus model/room/paired-date when known.
  static Future<void> _showSessionInfo(
    BuildContext context,
    PeerRecord peer,
    RoomInfo? room,
    String name,
  ) {
    final owner = (peer.nickname?.isNotEmpty ?? false)
        ? peer.nickname!
        : peer.sessionName.isNotEmpty
        ? peer.sessionName
        : peer.remoteEpk.substring(0, 8);
    final model = room?.model;
    final paired = peer.pairedAt.contains('T')
        ? peer.pairedAt.split('T').first
        : peer.pairedAt;
    return showDialog<void>(
      context: context,
      builder: (dCtx) {
        final colors = dCtx.colors;
        return AlertDialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: colors.border),
          ),
          title: Text(
            'Session info',
            style: TextStyle(fontSize: 15, color: colors.text),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Name', value: name),
              _InfoRow(label: 'Path', value: room?.cwd ?? '—'),
              _InfoRow(label: 'Owner', value: owner),
              if (model != null && model.isNotEmpty)
                _InfoRow(label: 'Model', value: model),
              _InfoRow(label: 'Room', value: room?.roomId ?? '—'),
              _InfoRow(label: 'Paired', value: paired),
            ],
          ),
          actions: [
            if (room?.cwd != null)
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: room!.cwd!)),
                icon: const Icon(LucideIcons.copy, size: 18),
                label: const Text('Copy path'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(
                'Close',
                style: TextStyle(fontFamily: kMonoFamily, color: colors.accent),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _roomDisplayName(
    RoomInfo? room,
    ChatState state,
    String? initialTitle,
  ) {
    if (room != null) {
      if (room.name != null && room.name!.isNotEmpty) return room.name!;
      final cwd = room.cwd;
      if (cwd != null && cwd.isNotEmpty) {
        final segs = cwd.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) return segs.last;
      }
    }
    if (state is ChatReady && state.messages.isNotEmpty) {
      return _inferSessionName(state.messages);
    }
    // Plan/24-fix-title: Home knows the peer label before /chat
    // mounts; use it instead of the generic 'Remote Pi' placeholder
    // while we wait for the first room_meta_updated to populate
    // `room.name`.
    if (initialTitle != null && initialTitle.isNotEmpty) return initialTitle;
    return 'Agent';
  }

  static String _peerDisplayName(PeerRecord? peer, String? fallback) {
    if (peer == null) {
      // Plan/32g: while the ViewModel hasn't loaded the PeerRecord yet, fall
      // back to the device label Home passed (initialDevice) — same value the
      // PeerRecord resolves to, so no flicker on load.
      if (fallback != null && fallback.isNotEmpty) return fallback;
      return '—';
    }
    if (peer.nickname != null && peer.nickname!.isNotEmpty) {
      return peer.nickname!;
    }
    if (peer.sessionName.isNotEmpty) return peer.sessionName;
    return peer.remoteEpk.substring(0, 8);
  }

  Widget _buildBody(BuildContext context, ChatState state, ChatViewModel vm) {
    final hideToolCalls = context.watch<Preferences>().hideToolCalls;
    return switch (state) {
      // Edge case: opened /chat without a peer (e.g. peer revoked while
      // user was here). The chat is not the place to pair — render
      // a minimal empty state without an action. User navigates back
      // and uses Home / Settings → pairing.
      ChatNoPeer() => const _EmptyState(
        icon: LucideIcons.messageCircle,
        message: 'No active device',
      ),
      ChatConnecting() => const _EmptyState(
        icon: LucideIcons.refreshCw,
        message: 'Connecting…',
      ),
      ChatFatalError(:final message) => _EmptyState(
        icon: LucideIcons.circleAlert,
        title: "Can't open this session",
        message: message,
        actionLabel: 'Back to agents',
        onAction: () => context.go('/home'),
      ),
      ChatReady(:final messages, :final streaming) => () {
        final visible = hideToolCalls
            ? messages.where((m) => m is! ToolEvent).toList()
            : messages;
        // Empty body → the default placeholder (Pi brand icon + "Nothing
        // here"), shown whenever there's nothing to render — including while
        // reconnecting (the reconnect handshake never swaps the body).
        if (visible.isEmpty &&
            streaming == null &&
            state.answeredQuestions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No messages yet. Say what you want ${_roomDisplayName(vm.activeRoom, state, widget.initialTitle)} to do.',
                textAlign: TextAlign.center,
                style: context.typo.caption.copyWith(
                  color: context.colors.ink2,
                ),
              ),
            ),
          );
        }
        return ChatMessageList(
          messages: visible,
          streaming: streaming,
          answeredQuestions: state.answeredQuestions,
          onRetry: state.readOnly
              ? null
              : (message) => vm.sendMessage(message.text, image: message.image),
          onDecide: (id, decision) => vm.approveTool(id, decision),
        );
      }(),
    };
  }

  Widget _buildInput(BuildContext context, ChatState state, ChatViewModel vm) {
    if (state is ChatFatalError ||
        state is ChatNoPeer ||
        state is ChatReady && state.pairingRevoked) {
      return const SizedBox.shrink();
    }
    final isReady = state is ChatReady;
    final isOffline = isReady && state.isOffline;
    final isRevoked = isReady && state.pairingRevoked;
    final isPeerOffline = isReady && state.peerOfflineReason != null;
    // Live relay-reported offline (no `bye`): Pi is just not reachable.
    final isPresenceOffline = isReady && state.peerPresence is PresenceOffline;
    // Plan/31 — the composer is locked + the send button becomes "stop" for
    // the WHOLE working turn (send/echo → agent_done), not just the narrow
    // token-streaming window. Driven by the broad working signal so it matches
    // the AppBar/Home "working" indicator.
    final isWorking = isReady && vm.isWorking;
    final cancelId = vm.cancelTargetId;
    // Attachments require the same live channel as the composer.
    final actionsEnabled =
        isReady &&
        !state.isConnecting &&
        !isOffline &&
        !isRevoked &&
        !isPeerOffline &&
        !isPresenceOffline;

    return InputBar(
      disabled:
          !isReady ||
          state.isConnecting ||
          isOffline ||
          isRevoked ||
          isPeerOffline ||
          isPresenceOffline,
      streaming: isWorking,
      onCancel: cancelId != null
          ? () async {
              await vm.cancel(cancelId);
              if (mounted) setState(() => _stopRequested = true);
            }
          : null,
      agentName: _roomDisplayName(vm.activeRoom, state, widget.initialTitle),
      disabledPlaceholder:
          state is ChatConnecting || state is ChatReady && state.isConnecting
          ? 'Connecting…'
          : isOffline || isPeerOffline || isPresenceOffline
          ? 'Mac is offline — read only'
          : null,
      queuedMessages: isReady ? state.queuedMessages : const [],
      onSetQueued: vm.queueMessage,
      onClearQueued: vm.clearQueuedMessage,
      // Plan/29 — hold-to-talk voice input. The VM is route-scoped (bound in
      // app_router alongside ChatViewModel); InputBar listens to it directly,
      // so a read() is enough here.
      voice: context.read<VoiceInputViewModel>(),
      onVoiceHint: _handleVoiceHint,
      // Plan/30 — image attachments. takeImageForSend() reads + clears the
      // attached image so the inline image rides along with the (optionally
      // empty) caption. Attach-button gating by vision / already-attached is
      // internal to InputBar; the host only gates by channel availability.
      attachment: context.read<AttachmentViewModel>(),
      onOpenAttach: actionsEnabled
          ? () => _openAttach(context, context.read<AttachmentViewModel>())
          : null,
      onSend: (text) {
        final image = context.read<AttachmentViewModel>().takeImageForSend();
        setState(() => _stopRequested = false);
        vm.sendMessage(text, image: image);
      },
    );
  }

  /// Open the Camera/Gallery sheet and drive the picker. Captures the
  /// messenger up front so a permission-denied hint can deep-link to Settings
  /// after the async pick.
  static Future<void> _openAttach(
    BuildContext context,
    AttachmentViewModel vm,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await showAttachSheet(context);
    if (source == null) return;
    AttachHint? hint;
    final sub = vm.hints.listen((h) => hint = h);
    switch (source) {
      case AttachSource.camera:
        await vm.pickFromCamera();
      case AttachSource.gallery:
        await vm.pickFromGallery();
    }
    await Future<void>.delayed(Duration.zero); // flush the hint microtask
    await sub.cancel();
    if (hint != null) _handleAttachHint(messenger, hint!);
  }

  static void _handleAttachHint(
    ScaffoldMessengerState messenger,
    AttachHint hint,
  ) {
    messenger.hideCurrentSnackBar();
    switch (hint) {
      case AttachHint.cameraPermissionDenied:
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Camera access is off — enable it in Settings to attach a photo.',
            ),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Settings',
              onPressed: AppSettings.openAppSettings,
            ),
          ),
        );
      case AttachHint.pickFailed:
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't attach that image."),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _handleVoiceHint(VoiceHint hint) {
    setState(() {
      _voicePermission = hint == VoiceHint.permissionDenied;
      _voiceHint = _voicePermission
          ? 'Microphone access is off — enable it in Settings to dictate.'
          : 'Hold the mic to talk';
    });
    _voiceDismiss?.cancel();
    _voiceDismiss = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _voiceHint = null);
    });
  }

  static String _inferSessionName(List<ChatMessage> msgs) {
    for (final m in msgs) {
      if (m is UserMsg) return m.text.substring(0, m.text.length.clamp(0, 32));
    }
    return 'Agent';
  }
}

// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: title != null ? colors.error : colors.ink2,
              size: 32,
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                style: context.typo.title2,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.typo.body.copyWith(color: colors.ink2),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                ),
                child: Text(actionLabel!, style: context.typo.headline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One labelled key/value row in the session-info dialog. The value is
/// selectable so the user can copy the path / device name.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              color: colors.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: TextStyle(fontSize: 13, color: colors.text),
          ),
        ],
      ),
    );
  }
}
