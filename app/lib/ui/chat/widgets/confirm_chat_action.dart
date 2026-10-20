import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/widgets/confirm_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

Future<bool> confirmChatAction(
  BuildContext context, {
  required bool newSession,
  SessionSelection? sessionSelection,
}) async {
  final selection = sessionSelection ?? context.read<SessionSelection?>();
  final before = selection?.current;
  final confirmed = await showConfirmSheet(
    context,
    title: newSession ? 'Start a new session?' : 'Compact context?',
    message: newSession
        ? 'The agent starts a fresh conversation. Cached messages for this session will be cleared on this phone.'
        : 'Summarises earlier turns to free context.',
    confirmLabel: newSession ? 'New session' : 'Compact',
    destructive: newSession,
  );
  final after = selection?.current;
  return confirmed &&
      before?.epk == after?.epk &&
      before?.roomId == after?.roomId;
}
