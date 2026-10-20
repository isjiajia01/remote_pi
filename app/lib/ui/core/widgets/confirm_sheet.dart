import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:app/ui/core/themes/themes.dart';

/// Returns true only when the user selects the confirming verb before expiry.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  DateTime? expiresAt,
}) async {
  final confirmed = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (sheetContext) => _ConfirmSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      expiresAt: expiresAt,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    this.expiresAt,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final DateTime? expiresAt;
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  Timer? _timer;
  bool get _expired =>
      widget.expiresAt != null && !DateTime.now().isBefore(widget.expiresAt!);
  @override
  void initState() {
    super.initState();
    if (widget.expiresAt != null) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt?.difference(DateTime.now()).inSeconds;
    return CupertinoActionSheet(
      title: Text(widget.title, style: context.typo.title2),
      message: Text(
        '${widget.message}${remaining == null
            ? ''
            : _expired
            ? '\nExpired'
            : '\nExpires in ${remaining + 1}s'}',
        style: context.typo.footnote,
      ),
      actions: [
        IgnorePointer(
          ignoring: _expired,
          child: CupertinoActionSheetAction(
            isDestructiveAction: widget.destructive,
            onPressed: () {
              if (!_expired) Navigator.of(context).pop(true);
            },
            child: Opacity(
              opacity: _expired ? 0.4 : 1,
              child: Text(
                widget.confirmLabel,
                style: context.typo.headline.copyWith(
                  color: widget.destructive
                      ? context.colors.error
                      : context.colors.accent,
                ),
              ),
            ),
          ),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          'Cancel',
          style: context.typo.headline.copyWith(color: context.colors.accent),
        ),
      ),
    );
  }
}
