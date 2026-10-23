import 'dart:async';
import 'package:app/ui/core/interaction_feedback.dart';

import 'package:app/data/images/image_picker_service.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/attachment/states/attachment_state.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/voice/states/voice_input_state.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/chat/voice/widgets/recording_strip.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// InputBar — bottom message composer.
// - Disabled (grayed) when offline.
// - During streaming, empty composer shows Stop; typed text sends steering.
// - Quick actions live in the navigation menu and context strip.
// - Plan/29 — when [voice] is provided, the mic becomes hold-to-talk:
//   long-press starts recording (a WhatsApp-style RecordingStrip replaces
//   the row), slide left past the threshold cancels, release transcribes
//   and drops the text into the (empty) field for manual review/send. The
//   recognizer never auto-sends.

/// One-shot UI hint the composer asks the host page to surface (snackbar /
/// settings deep-link). Keeps InputBar free of `BuildContext`-bound effects.
enum VoiceHint {
  /// User tapped the mic instead of holding it.
  holdToTalk,

  /// Mic / speech permission was denied — guide to system Settings (#10).
  permissionDenied,
}

class InputBar extends StatefulWidget {
  final bool disabled; // offline or no peer
  final bool streaming; // show cancel instead of send
  final String agentName;
  final String? disabledPlaceholder;
  final void Function(String text) onSend;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenQuickActions;
  final VoidCallback? onStartAudio;

  /// Pi-side queued follow-ups. Empty means no queued messages.
  final List<QueuedMsg> queuedMessages;
  final void Function(String text)? onSetQueued;
  final void Function(String id)? onClearQueued;

  /// Plan/29 — voice-input ViewModel. When null the mic falls back to the
  /// legacy [onStartAudio] tap (and existing tests pump InputBar without it).
  final VoiceInputViewModel? voice;

  /// Plan/29 — surfaces a [VoiceHint] to the host page for a snackbar /
  /// settings deep-link.
  final void Function(VoiceHint hint)? onVoiceHint;

  /// Plan/30 — image-attachment ViewModel (preview state + model vision).
  /// Null in tests / when attachments aren't wired.
  final AttachmentViewModel? attachment;

  /// Plan/30 — open the Camera/Gallery sheet. Null disables the attach
  /// button (offline/streaming); vision/has-image gating is internal.
  final VoidCallback? onOpenAttach;

  const InputBar({
    super.key,
    required this.onSend,
    this.onCancel,
    this.onOpenQuickActions,
    this.onStartAudio,
    this.queuedMessages = const [],
    this.onSetQueued,
    this.onClearQueued,
    this.voice,
    this.onVoiceHint,
    this.attachment,
    this.onOpenAttach,
    this.disabled = false,
    this.streaming = false,
    this.agentName = 'agent',
    this.disabledPlaceholder,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  /// How far left the press must slide to arm slide-to-cancel (logical px).
  static const double _cancelThreshold = 90;

  final _controller = TextEditingController();
  // Owns the field's focus so we can intercept hardware Enter on its OWN
  // node (the primary/leaf focus). An ancestor Focus runs too late: the
  // FocusManager dispatches leaf→root, so the field's multiline newline
  // handling would consume Enter before an ancestor ever sees it.
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _onComposerKey);
  bool _empty = true;
  bool _cancelArmed = false;
  // True while the hold-to-talk gesture is active. Lets `_beginVoice` tell
  // whether the user is still holding once `startRecording` resolves — if not
  // (the permission prompt ended the hold), the recording is discarded.
  bool _holding = false;
  StreamSubscription<String>? _transcriptSub;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChange);
    _subscribeTranscripts();
  }

  @override
  void didUpdateWidget(InputBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.voice, widget.voice)) {
      _transcriptSub?.cancel();
      _subscribeTranscripts();
    }
  }

  void _subscribeTranscripts() {
    _transcriptSub = widget.voice?.transcripts.listen(_onTranscript);
  }

  void _onTranscript(String text) {
    if (!mounted || text.isEmpty) return; // empty → no-op (#12)
    // The field is empty by construction (mic only shows when empty), so we
    // replace rather than concatenate (#non-objetivo: no merge).
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  void _onTextChange() {
    final next = _controller.text.isEmpty;
    if (next == _empty) return;
    setState(() {
      _empty = next;
    });
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    _controller.removeListener(_onTextChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.disabled) return;
    final text = _controller.text.trim();
    // Plan/30 — an attached image makes an empty-caption send valid.
    final hasImage = widget.attachment?.hasImage ?? false;
    if (text.isEmpty && !hasImage) return;
    InteractionFeedback.action();
    _controller.clear();
    widget.onSend(text);
  }

  void _cancelTurn() {
    if (widget.disabled || widget.onCancel == null) return;
    InteractionFeedback.action();
    widget.onCancel!();
  }

  void _editQueued(QueuedMsg item) {
    if (!item.editable) return;
    widget.onClearQueued?.call(item.id);
    _controller.text = item.text;
    _controller.selection = TextSelection.collapsed(offset: item.text.length);
    _focusNode.requestFocus();
  }

  /// Hardware-keyboard behaviour (iPad keyboard case, etc.): plain Enter
  /// SENDS, Shift+Enter inserts a newline. On a touch soft-keyboard the
  /// newline arrives via `performAction` (not a key event), so this never
  /// fires there — the field keeps growing and the user sends with the
  /// composer button, exactly as before.
  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    // Don't intercept while disabled, or mid-IME-composition (a CJK
    // candidate is confirmed with Enter, not sent) — let the field/IME deal.
    if (widget.disabled || !_controller.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift+Enter → newline. Inserted explicitly (and consumed) so the
      // behaviour is identical on every platform instead of depending on
      // the framework's default multiline key handling.
      _insertNewlineAtCursor();
      return KeyEventResult.handled;
    }
    _submit();
    return KeyEventResult.handled;
  }

  /// Replaces the current selection (or inserts at the caret) with a newline
  /// and leaves the caret right after it.
  void _insertNewlineAtCursor() {
    final value = _controller.value;
    final sel = value.selection;
    if (!sel.isValid) {
      final text = '${value.text}\n';
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      return;
    }
    final text = '${sel.textBefore(value.text)}\n${sel.textAfter(value.text)}';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  // --- voice gesture ---------------------------------------------------------

  void _onVoiceStart() {
    _holding = true;
    if (_cancelArmed) setState(() => _cancelArmed = false);
    unawaited(_beginVoice());
  }

  Future<void> _beginVoice() async {
    final voice = widget.voice;
    if (voice == null) return;
    await voice.startRecording();
    if (!mounted) return;
    // Bug fix: on first use the OS permission prompt steals the hold — the
    // finger lifts to tap "Allow", so the press ends BEFORE recording actually
    // begins (state isn't VoiceRecording yet, so the release no-ops). When
    // `startRecording` then resolves and starts, the composer was left stuck
    // "recording" with no finger down. If the gesture is already over by the
    // time we get here, discard that phantom recording.
    if (!_holding && voice.state is VoiceRecording) {
      await voice.cancel();
      if (!mounted) return;
    }
    final s = voice.state;
    if (s is VoiceUnavailable &&
        s.reason == VoiceUnavailableReason.permissionDenied) {
      widget.onVoiceHint?.call(VoiceHint.permissionDenied);
    }
  }

  void _onVoiceMove(LongPressMoveUpdateDetails details) {
    if (widget.voice?.state is! VoiceRecording) return;
    final armed = details.offsetFromOrigin.dx < -_cancelThreshold;
    if (armed != _cancelArmed) setState(() => _cancelArmed = armed);
  }

  void _onVoiceEnd() {
    _holding = false;
    final voice = widget.voice;
    final armed = _cancelArmed;
    if (_cancelArmed) setState(() => _cancelArmed = false);
    if (voice == null || voice.state is! VoiceRecording) return;
    if (armed) {
      unawaited(voice.cancel());
    } else {
      // Transcript arrives via voice.transcripts → _onTranscript, the same
      // path the 60s cap uses — release never populates the field directly.
      unawaited(voice.stopAndTranscribe());
    }
  }

  void _onVoiceTap() => widget.onVoiceHint?.call(VoiceHint.holdToTalk);

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      if (widget.voice != null) widget.voice!,
      if (widget.attachment != null) widget.attachment!,
    ];
    if (listenables.isEmpty) return _composer(context);
    // Rebuild on every voice/attachment emit (tick / level / availability /
    // pick) so the strip + preview animate even when no ancestor watches them.
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _composer(context),
    );
  }

  Widget _composer(BuildContext context) {
    final colors = context.colors;
    final voiceState = widget.voice?.state;
    final attachState = widget.attachment?.state;
    final canInteract = !widget.disabled;
    final recording = voiceState is VoiceRecording;
    final transcribing = voiceState is VoiceTranscribing;
    final showStrip = recording || transcribing;
    final voiceUnsupported =
        voiceState is VoiceUnavailable &&
        voiceState.reason == VoiceUnavailableReason.unsupported;

    // Plan/30 — attachment.
    final hasImage = attachState is AttachmentAttached;
    final visionBlocked = attachState?.attachBlockedByVision ?? false;
    final hasContent = !_empty || hasImage;
    final attachEnabled =
        widget.onOpenAttach != null &&
        canInteract &&
        !widget.streaming &&
        !showStrip &&
        !visionBlocked &&
        !hasImage;

    // During a working turn with typed content, the main action sends steering;
    // keep a compact Stop affordance beside it so cancellation remains reachable.
    final showInlineStop =
        widget.streaming &&
        hasContent &&
        canInteract &&
        !showStrip &&
        widget.onCancel != null;

    return Opacity(
      opacity: widget.disabled ? .4 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage)
                  _AttachmentPreview(
                    image: attachState.image,
                    onRemove: widget.disabled
                        ? null
                        : widget.attachment!.removeImage,
                  ),
                if (widget.streaming) ...[
                  SizedBox(
                    height: 2,
                    child: LinearProgressIndicator(
                      key: const Key('composer-working-line'),
                      value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
                      color: colors.working,
                      backgroundColor: colors.surface,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (widget.queuedMessages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${widget.queuedMessages.length} queued',
                      style: context.typo.caption.copyWith(color: colors.ink2),
                    ),
                  ),
                for (final item in widget.queuedMessages)
                  _QueuedMessagePreview(
                    text: item.text,
                    editable: item.editable,
                    onTap: item.editable && canInteract
                        ? () => _editQueued(item)
                        : null,
                    onClear: item.editable && canInteract
                        ? () => widget.onClearQueued?.call(item.id)
                        : null,
                  ),
                Row(
                  children: [
                    _AttachButton(
                      enabled: attachEnabled,
                      onTap: widget.onOpenAttach,
                    ),
                    const SizedBox(width: 10),
                    // Text field (doubles as the image caption when one is set).
                    Expanded(
                      child: TextField(
                        // Intercept hardware Enter on the field's OWN focus
                        // node (the primary/leaf): plain Enter sends,
                        // Shift+Enter newlines — see _onComposerKey. Must be
                        // the leaf, not an ancestor Focus, or the multiline
                        // newline handling consumes Enter first.
                        focusNode: _focusNode,
                        controller: _controller,
                        enabled: canInteract,
                        // Grow with the content: starts at one line, expands up
                        // to 6 then scrolls internally. On a touch soft-keyboard
                        // Enter inserts a newline; sending is via the composer
                        // button (hardware Enter sends — see _onComposerKey).
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: context.typo.chatBody,
                        cursorColor: colors.accent,
                        decoration: InputDecoration(
                          hintText: widget.disabled
                              ? (widget.disabledPlaceholder ?? 'Agent offline')
                              : widget.streaming
                              ? 'Steer current response…'
                              : hasImage
                              ? 'Add a caption…'
                              : 'Message ${widget.agentName}',
                          hintStyle: context.typo.chatBody.copyWith(
                            color: colors.ink2,
                          ),
                          constraints: const BoxConstraints(minHeight: 44),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: colors.inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(color: colors.border),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: colors.border.withValues(alpha: 0.5),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide(
                              color: colors.accent,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ComposerActionButton(
                      streaming: widget.streaming,
                      hasContent: hasContent,
                      disabled: widget.disabled,
                      onSendText: _submit,
                      onCancel: widget.onCancel == null ? null : _cancelTurn,
                      onStartAudio: widget.onStartAudio,
                      voiceEnabled: widget.voice != null,
                      voiceUnsupported: voiceUnsupported,
                      onVoiceLongPressStart: _onVoiceStart,
                      onVoiceLongPressMoveUpdate: _onVoiceMove,
                      onVoiceLongPressEnd: _onVoiceEnd,
                      onVoiceTap: _onVoiceTap,
                    ),
                    if (showInlineStop) ...[
                      const SizedBox(width: 8),
                      _InlineStopButton(onTap: _cancelTurn),
                    ],
                  ],
                ),
              ],
            ),
            // Recording strip — overlays the row (decision #11) while the mic's
            // GestureDetector stays mounted underneath so the same long-press
            // keeps feeding move/end events across the swap. IgnorePointer so
            // the overlay never steals the in-flight gesture.
            if (showStrip)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: colors.bg,
                    child: Center(
                      child: recording
                          ? RecordingStrip(
                              level: voiceState.level,
                              elapsed: voiceState.elapsed,
                              maxDuration:
                                  widget.voice?.maxDuration ??
                                  const Duration(seconds: 60),
                              cancelArmed: _cancelArmed,
                            )
                          : const _TranscribingStrip(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows the message committed for auto-send after the current turn ends.
/// Tapping pulls it back into the composer for edit and cancels the pending
/// auto-send; X drops it.
class _QueuedMessagePreview extends StatelessWidget {
  const _QueuedMessagePreview({
    required this.text,
    required this.editable,
    this.onTap,
    this.onClear,
  });

  final String text;
  final bool editable;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('input-bar-queued-preview'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(LucideIcons.clock, size: 16, color: colors.ink2),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.subhead,
                      ),
                      Text(
                        editable ? 'Queued · tap to edit' : 'Queued follow-up',
                        style: context.typo.caption.copyWith(
                          color: colors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    key: const Key('input-bar-clear-queued'),
                    tooltip: 'Clear queued message',
                    onPressed: onClear,
                    icon: Icon(LucideIcons.x, size: 16, color: colors.ink2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact Stop affordance shown beside Send while steering text is typed.
class _InlineStopButton extends StatelessWidget {
  const _InlineStopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      key: const Key('input-bar-inline-stop'),
      onTap: onTap,
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.ink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(LucideIcons.square600, color: colors.bg, size: 14),
          ),
        ),
      ),
    );
  }
}

/// Plan/30 — the attach (paperclip) button. Always visible; greyed + inert
/// when [enabled] is false (offline/streaming, a text-only model #9, or an
/// image is already attached).
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        key: const Key('input-bar-attach'),
        padding: EdgeInsets.zero,
        iconSize: 18,
        splashRadius: 18,
        tooltip: 'Attach image',
        icon: Icon(
          LucideIcons.plus,
          color: enabled
              ? context.colors.muted2
              : context.colors.muted.withValues(alpha: 0.35),
        ),
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

/// Plan/30 — the composer image preview: a rounded thumbnail with an "X" to
/// discard before sending (decision #4).
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.image, required this.onRemove});

  final PickedImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('attach-preview'),
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                image.bytes,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            Positioned(
              top: -4,
              right: 8,
              child: GestureDetector(
                key: const Key('attach-remove'),
                onTap: onRemove,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.border),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    LucideIcons.x,
                    size: 13,
                    color: context.colors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscribingStrip extends StatelessWidget {
  const _TranscribingStrip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const Key('transcribing-strip'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'transcribing…',
          style: context.typo.footnote.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}

/// The trailing action is determined by whole-turn working state and content.
enum ComposerMode { mic, send, stop, steer }

ComposerMode composerMode({required bool working, required bool hasContent}) =>
    working
    ? (hasContent ? ComposerMode.steer : ComposerMode.stop)
    : (hasContent ? ComposerMode.send : ComposerMode.mic);

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    required this.streaming,
    required this.hasContent,
    required this.disabled,
    required this.onSendText,
    required this.onCancel,
    required this.onStartAudio,
    required this.voiceEnabled,
    required this.voiceUnsupported,
    required this.onVoiceLongPressStart,
    required this.onVoiceLongPressMoveUpdate,
    required this.onVoiceLongPressEnd,
    required this.onVoiceTap,
  });

  final bool streaming;

  /// Text typed OR an image attached → the button is "send" (decision #6).
  final bool hasContent;
  final bool disabled;
  final VoidCallback onSendText;
  final VoidCallback? onCancel;
  final VoidCallback? onStartAudio;

  // Plan/29 voice wiring.
  final bool voiceEnabled;
  final bool voiceUnsupported;
  final VoidCallback onVoiceLongPressStart;
  final void Function(LongPressMoveUpdateDetails) onVoiceLongPressMoveUpdate;
  final VoidCallback onVoiceLongPressEnd;
  final VoidCallback onVoiceTap;

  ComposerMode get _mode =>
      composerMode(working: streaming, hasContent: hasContent);

  IconData get _icon => switch (_mode) {
    ComposerMode.stop => LucideIcons.square600,
    ComposerMode.send => LucideIcons.arrowUp,
    ComposerMode.steer => LucideIcons.cornerDownRight,
    ComposerMode.mic => LucideIcons.mic600,
  };

  VoidCallback? _resolveTap() {
    if (disabled) return null;
    return switch (_mode) {
      ComposerMode.stop => onCancel,
      ComposerMode.send || ComposerMode.steer => onSendText,
      ComposerMode.mic => onStartAudio,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Decision #9 edge — no on-device recognition anywhere: hide the mic so
    // the empty field shows just the attach placeholder (dictate via keyboard).
    if (_mode == ComposerMode.mic && voiceUnsupported) {
      return const SizedBox.shrink();
    }

    // Hold-to-talk mic (decision #4): long-press records, slide cancels,
    // release transcribes. A plain tap surfaces the "hold to talk" hint.
    if (_mode == ComposerMode.mic && voiceEnabled) {
      return GestureDetector(
        onTap: disabled ? null : onVoiceTap,
        onLongPressStart: disabled ? null : (_) => onVoiceLongPressStart(),
        onLongPressMoveUpdate: disabled ? null : onVoiceLongPressMoveUpdate,
        onLongPressEnd: disabled ? null : (_) => onVoiceLongPressEnd(),
        child: _button(context),
      );
    }

    return GestureDetector(
      key: const Key('input-bar-action'),
      onTap: _resolveTap(),
      child: _button(context),
    );
  }

  Widget _button(BuildContext context) {
    final colors = context.colors;
    final fill = switch (_mode) {
      ComposerMode.stop => colors.ink,
      ComposerMode.steer => colors.working,
      ComposerMode.send => colors.accent,
      ComposerMode.mic => colors.surface2,
    };
    final foreground = switch (_mode) {
      ComposerMode.stop => colors.bg,
      ComposerMode.mic => colors.ink2,
      ComposerMode.send || ComposerMode.steer => colors.onAccent,
    };
    final label = switch (_mode) {
      ComposerMode.mic => 'Hold to talk',
      ComposerMode.send => 'Send',
      ComposerMode.stop => 'Stop',
      ComposerMode.steer => 'Steer',
    };
    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Icon(
              _icon,
              key: ValueKey(_mode),
              color: foreground,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
