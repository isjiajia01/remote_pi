import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

Future<bool> showRevokeConfirmDialog(
  BuildContext context, {
  required PeerRecord peer,
}) => showConfirmSheet(
  context,
  title:
      'Remove ${(peer.nickname?.isNotEmpty ?? false) ? peer.nickname : peer.sessionName}?',
  message: 'This phone will stop seeing its agents. You can pair again later.',
  confirmLabel: 'Remove',
  destructive: true,
);
