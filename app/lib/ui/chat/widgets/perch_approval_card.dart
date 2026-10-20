import 'dart:async';
import 'dart:convert';

import 'package:app/domain/contracts/approval_client.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'package:app/ui/core/widgets/confirm_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Perch's explicit challenge; legacy tool cards remain informational.
class PerchApprovalCard extends StatefulWidget {
  const PerchApprovalCard({
    super.key,
    required this.approval,
    required this.onDecide,
    this.enabled = true,
  });
  final BoundApproval approval;
  final Future<void> Function(PerchApprovalDecision) onDecide;
  final bool enabled;
  @override
  State<PerchApprovalCard> createState() => _PerchApprovalCardState();
}

class _PerchApprovalCardState extends State<PerchApprovalCard> {
  Timer? _timer;
  bool _expanded = false;
  bool _busy = false;
  String? _error;
  PerchToolApprovalRequest get request => widget.approval.request;
  bool get _expired => request.isExpired(DateTime.now());
  bool get _enabled => widget.enabled && !_busy && !_expired;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _decide(PerchApprovalDecision decision) async {
    if (!_enabled) return;
    final verb = decision == PerchApprovalDecision.allow ? 'Allow' : 'Deny';
    setState(() {
      _busy = true;
      _error = null;
    });
    final confirmed = await showConfirmSheet(
      context,
      title: '$verb ${request.tool}?',
      message: const JsonEncoder.withIndent('  ').convert(request.args),
      confirmLabel: verb,
      destructive: decision == PerchApprovalDecision.deny,
      expiresAt: request.expiresAt,
    );
    if (!mounted) return;
    if (!confirmed || _expired || !widget.enabled) {
      setState(() => _busy = false);
      return;
    }
    try {
      await widget.onDecide(decision);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Couldn’t send the decision. Check the connection and retry.',
        );
      }
    } on StateError {
      if (mounted) {
        setState(() => _error = 'This approval is no longer available.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds =
        (request.expiresAt.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(12),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  LucideIcons.shieldCheck,
                  size: 16,
                  color: context.colors.ink2,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(request.tool, style: context.typo.mono)),
                Text(
                  _expired ? 'Expired' : 'Expires in ${seconds}s',
                  style: context.typo.caption,
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: context.colors.ink3,
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    const JsonEncoder.withIndent('  ').convert(request.args),
                    style: context.typo.monoCode,
                  ),
                ),
              ),
            ),
          if (_error != null)
            AppBanner(message: _error!, variant: BannerVariant.error),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final decision in PerchApprovalDecision.values)
                Opacity(
                  opacity: _enabled ? 1 : 0.4,
                  child: CupertinoButton(
                    onPressed: _enabled ? () => _decide(decision) : null,
                    child: Text(
                      decision == PerchApprovalDecision.allow
                          ? 'Allow'
                          : 'Deny',
                      style: context.typo.headline.copyWith(
                        color: decision == PerchApprovalDecision.deny
                            ? context.colors.error
                            : context.colors.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
