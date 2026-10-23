import 'dart:async';
import 'package:app/ui/core/interaction_feedback.dart';

import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/pairing/states/pairing_error_copy.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/pairing/widgets/nickname_sheet.dart';
import 'package:app/ui/pairing/widgets/paste_qr_sheet.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

class PairingPage extends StatelessWidget {
  const PairingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.bg,
    appBar: AppBar(title: Text('Pair a machine', style: context.typo.title2)),
    body: SafeArea(
      child: PairingFlow(
        onPaired: () {
          final s = context.read<PairingViewModel>().state;
          context.go(
            '/home',
            extra: s is PairingPaired
                ? {'pairedPeerEpk': s.peer.remoteEpk}
                : null,
          );
        },
        onChangeRelay: () => context.push('/settings'),
      ),
    ),
  );
}

/// Shared by the onboarding pair step and Settings' add-machine route.
class PairingFlow extends StatefulWidget {
  const PairingFlow({
    super.key,
    required this.onPaired,
    required this.onChangeRelay,
    this.onSkip,
  });
  final VoidCallback onPaired;
  final VoidCallback onChangeRelay;
  final VoidCallback? onSkip;

  @override
  State<PairingFlow> createState() => _PairingFlowState();
}

class _PairingFlowState extends State<PairingFlow> {
  final _scanner = MobileScannerController();
  bool _scannerActive = true;
  bool _postPairStarted = false;
  PairingState? _feedbackState;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  void _submitRaw(String raw) {
    if (!_scannerActive) return;
    _scannerActive = false;
    unawaited(_scanner.stop());
    unawaited(context.read<PairingViewModel>().onQrScanned(raw));
  }

  void _retry() {
    context.read<PairingViewModel>().retry();
    _scannerActive = true;
  }

  Future<void> _paste({bool retry = false}) async {
    if (retry) _retry();
    await showPasteQrSheet(context, onSubmit: _submitRaw);
  }

  Future<void> _postPair(String? hint) async {
    final vm = context.read<PairingViewModel>();
    final name = await showNicknameSheet(context, defaultName: hint);
    if (!mounted) return;
    await vm.applyNickname(name);
    if (mounted) widget.onPaired();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PairingViewModel>();
    final state = vm.state;
    if (!identical(state, _feedbackState)) {
      final previous = _feedbackState;
      _feedbackState = state;
      if (previous != null &&
          (state is PairingPaired || state is PairingError)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) InteractionFeedback.result();
        });
      }
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: switch (state) {
        PairingConnecting() => PairingConnectingView(
          state: state,
          host: vm.relayHost,
          onCancel: () async {
            await vm.cancel();
            if (mounted) _scannerActive = true;
          },
        ),
        PairingError() => PairingErrorView(
          error: state,
          host: vm.relayHost,
          onRetry: _retry,
          onPaste: () => _paste(retry: true),
          onChangeRelay: () {
            _retry();
            widget.onChangeRelay();
          },
        ),
        PairingPaired() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.circleCheck,
                color: context.colors.online,
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                'Paired with ${state.hostnameHint ?? state.peer.sessionName}',
                style: context.typo.title2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your Mac is ready. Open agents to see its Pi sessions.',
                style: context.typo.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Open agents',
                onPressed: _postPairStarted
                    ? null
                    : () {
                        setState(() => _postPairStarted = true);
                        unawaited(_postPair(state.hostnameHint));
                      },
              ),
            ],
          ),
        ),
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '1  On your Mac run  /remote-pi pair',
                                style: context.typo.monoSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy command',
                              onPressed: () => Clipboard.setData(
                                const ClipboardData(text: '/remote-pi pair'),
                              ),
                              icon: Icon(
                                LucideIcons.copy,
                                size: 20,
                                color: context.colors.accent,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '2  Scan the QR it shows',
                          style: context.typo.subhead,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _scanner,
                            onDetect: (capture) {
                              final raw =
                                  capture.barcodes.firstOrNull?.rawValue;
                              if (raw != null) _submitRaw(raw);
                            },
                            errorBuilder: (context, error) => Container(
                              color: context.colors.surface,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.cameraOff,
                                    color: context.colors.ink2,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    error.errorCode ==
                                            MobileScannerErrorCode
                                                .permissionDenied
                                        ? 'Camera access is off'
                                        : 'Camera is unavailable',
                                    style: context.typo.title2,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  PrimaryButton(
                                    label: 'Open Settings',
                                    onPressed: () =>
                                        AppSettings.openAppSettings(),
                                  ),
                                  SecondaryButton(
                                    label: 'Paste code instead',
                                    onPressed: _paste,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const IgnorePointer(child: _CornerBrackets()),
                        ],
                      ),
                    ),
                  ),
                  SecondaryButton(
                    label: 'Paste code instead',
                    onPressed: _paste,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'Relay: ${vm.relayHost}',
                          style: context.typo.footnote.copyWith(
                            color: context.colors.ink2,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onChangeRelay,
                        child: Text(
                          'Change',
                          style: context.typo.footnote.copyWith(
                            color: context.colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.onSkip != null)
              SecondaryButton(label: 'Scan later', onPressed: widget.onSkip),
          ],
        ),
      },
    );
  }
}

class PairingConnectingView extends StatefulWidget {
  const PairingConnectingView({
    super.key,
    required this.state,
    required this.host,
    required this.onCancel,
  });
  final PairingConnecting state;
  final String host;
  final VoidCallback onCancel;
  @override
  State<PairingConnectingView> createState() => _PairingConnectingViewState();
}

class _PairingConnectingViewState extends State<PairingConnectingView> {
  late final DateTime _fallbackStart = DateTime.now();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Reaching relay ${widget.host}',
      'Waiting for ${widget.state.sessionName} to answer',
      'Confirming pairing',
    ];
    final elapsed = DateTime.now()
        .difference(widget.state.startedAt ?? _fallbackStart)
        .inSeconds;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final stage in PairingStage.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: stage.index < widget.state.stage.index
                            ? Icon(
                                LucideIcons.check,
                                color: context.colors.online,
                                size: 20,
                              )
                            : stage == widget.state.stage
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colors.accent,
                                ),
                              )
                            : Icon(
                                LucideIcons.dot,
                                color: context.colors.ink3,
                                size: 20,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        labels[stage.index],
                        style: context.typo.subhead.copyWith(
                          color: stage.index > widget.state.stage.index
                              ? context.colors.ink2
                              : context.colors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '$elapsed s',
              textAlign: TextAlign.right,
              style: context.typo.caption.copyWith(
                color: context.colors.ink2,
                fontFeatures: AppTypography.tabularFigures,
              ),
            ),
            const SizedBox(height: 24),
            SecondaryButton(label: 'Cancel', onPressed: widget.onCancel),
          ],
        ),
      ),
    );
  }
}

class PairingErrorView extends StatelessWidget {
  const PairingErrorView({
    super.key,
    required this.error,
    required this.host,
    required this.onRetry,
    required this.onPaste,
    required this.onChangeRelay,
  });
  final PairingError error;
  final String host;
  final VoidCallback onRetry;
  final VoidCallback onPaste;
  final VoidCallback onChangeRelay;

  @override
  Widget build(BuildContext context) {
    final copy = PairingErrorCopy.forError(error, host);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 32,
              color: context.colors.error,
            ),
            const SizedBox(height: 16),
            Text(
              copy.title,
              style: context.typo.title2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              copy.body,
              style: context.typo.body.copyWith(color: context.colors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: copy.primary,
              onPressed: error.canRetry ? onRetry : null,
            ),
            if (copy.secondary != null)
              SecondaryButton(
                label: copy.secondary!,
                onPressed: copy.secondary == 'Change relay'
                    ? onChangeRelay
                    : onPaste,
              ),
            ExpansionTile(
              title: Text('Details', style: context.typo.footnote),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    '${error.code}\n${error.message}',
                    style: context.typo.monoSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy details',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: '${error.code}\n${error.message}'),
                  ),
                  icon: Icon(
                    LucideIcons.copy,
                    size: 20,
                    color: context.colors.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BracketPainter());
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ]) {
      final x = corner.dx == 0 ? 18.0 : -18.0;
      final y = corner.dy == 0 ? 18.0 : -18.0;
      final origin =
          corner + Offset(corner.dx == 0 ? 16 : -16, corner.dy == 0 ? 16 : -16);
      canvas.drawLine(origin, origin + Offset(x, 0), paint);
      canvas.drawLine(origin, origin + Offset(0, y), paint);
    }
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}
