import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'package:flutter/widgets.dart';

/// One persistent condition, with revocation taking priority over offline.
class ChatStatusBanner extends StatelessWidget {
  const ChatStatusBanner({
    super.key,
    required this.state,
    required this.machine,
    required this.onReconnect,
    required this.onPairAgain,
  });
  final ChatState state;
  final String machine;
  final VoidCallback onReconnect;
  final VoidCallback onPairAgain;

  @override
  Widget build(BuildContext context) {
    final current = state;
    if (current is ChatReady && current.pairingRevoked) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppBanner(
          message: 'This phone was removed from $machine',
          variant: BannerVariant.error,
          actionLabel: 'Pair again',
          onAction: onPairAgain,
        ),
      );
    }
    if (current is ChatConnecting ||
        current is ChatReady && current.isConnecting) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: AppBanner(message: 'Connecting…'),
      );
    }
    if (current is! ChatReady) return const SizedBox.shrink();
    if (current.isOffline ||
        current.peerPresence is PresenceOffline ||
        current.peerOfflineReason != null) {
      final reason = switch (current.peerOfflineReason) {
        'peer_stop' => 'Pi was closed',
        'session_replaced' => 'Session opened elsewhere',
        'shutdown' => 'Mac shut down',
        _ => null,
      };
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppBanner(
          message:
              '$machine is offline — read only${reason == null ? '' : ' · $reason'}',
          actionLabel: 'Reconnect',
          onAction: onReconnect,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
