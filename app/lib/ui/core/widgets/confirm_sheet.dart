import 'package:flutter/cupertino.dart';
import 'package:app/ui/core/themes/themes.dart';

/// Returns true only when the user selects the confirming verb.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(title, style: context.typo.title2),
      message: Text(message, style: context.typo.footnote),
      actions: [
        CupertinoActionSheetAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.of(sheetContext).pop(true),
          child: Text(
            confirmLabel,
            style: context.typo.headline.copyWith(
              color: destructive ? context.colors.error : context.colors.accent,
            ),
          ),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(false),
        child: Text(
          'Cancel',
          style: context.typo.headline.copyWith(color: context.colors.accent),
        ),
      ),
    ),
  );
  return confirmed ?? false;
}
