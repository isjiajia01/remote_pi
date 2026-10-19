import 'dart:async';
import 'dart:io';

import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/relay_reachability.dart';

/// A bare WebSocket upgrade verifies reachability without authenticating a peer.
class WsRelayReachability implements RelayReachability {
  @override
  Future<RelayCheckResult> check(String url) async {
    final clock = Stopwatch()..start();
    var timedOut = false;
    final opening = WebSocket.connect(toWsRelayUrl(url));
    // Dart cannot cancel an upgrade. Close a socket that arrives after timeout.
    unawaited(
      opening.then<void>((socket) async {
        if (timedOut) await socket.close();
      }, onError: (Object _, StackTrace _) {}),
    );
    try {
      final socket = await opening.timeout(const Duration(seconds: 8));
      final elapsed = clock.elapsed;
      unawaited(socket.close());
      return RelayCheckResult.reachable(elapsed);
    } on TimeoutException {
      timedOut = true;
      return const RelayCheckResult.failed(RelayCheckFailure.timeout);
    } on IOException {
      return const RelayCheckResult.failed(RelayCheckFailure.unreachable);
    }
  }
}
