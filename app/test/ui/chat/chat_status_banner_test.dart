import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/widgets/chat_status_banner.dart';
import 'package:app/ui/core/widgets/app_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ChatState state, {
    VoidCallback? reconnect,
    VoidCallback? pair,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatStatusBanner(
          state: state,
          machine: 'Studio Mac',
          onReconnect: reconnect ?? () {},
          onPairAgain: pair ?? () {},
        ),
      ),
    ),
  );

  for (final state in [
    const ChatConnecting(),
    const ChatReady(messages: [], isConnecting: true),
  ]) {
    testWidgets('$state has neutral connecting banner', (tester) async {
      await pump(tester, state);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(
        tester.widget<AppBanner>(find.byType(AppBanner)).variant,
        BannerVariant.neutral,
      );
    });
  }

  for (final state in [
    const ChatReady(messages: [], isOffline: true),
    const ChatReady(messages: [], peerPresence: PresenceOffline(sinceTs: 0)),
  ]) {
    testWidgets('$state is read only with reconnect action', (tester) async {
      var calls = 0;
      await pump(tester, state, reconnect: () => calls++);
      expect(find.text('Studio Mac is offline — read only'), findsOneWidget);
      expect(state.readOnly, isTrue);
      expect(
        tester.widget<AppBanner>(find.byType(AppBanner)).variant,
        BannerVariant.neutral,
      );
      await tester.tap(find.text('Reconnect'));
      expect(calls, 1);
    });
  }

  for (final reason in {
    'peer_stop': 'Pi was closed',
    'session_replaced': 'Session opened elsewhere',
    'shutdown': 'Mac shut down',
  }.entries) {
    testWidgets('offline ${reason.key} explains cause', (tester) async {
      await pump(
        tester,
        ChatReady(messages: const [], peerOfflineReason: reason.key),
      );
      expect(find.textContaining(reason.value), findsOneWidget);
    });
  }

  testWidgets('revocation takes priority, error + Pair again', (tester) async {
    var calls = 0;
    await pump(
      tester,
      const ChatReady(messages: [], isOffline: true, pairingRevoked: true),
      pair: () => calls++,
    );
    expect(find.text('This phone was removed from Studio Mac'), findsOneWidget);
    expect(find.text('Reconnect'), findsNothing);
    expect(
      tester.widget<AppBanner>(find.byType(AppBanner)).variant,
      BannerVariant.error,
    );
    await tester.tap(find.text('Pair again'));
    expect(calls, 1);
  });

  testWidgets('online has no persistent banner', (tester) async {
    await pump(
      tester,
      const ChatReady(messages: [], peerPresence: PresenceOnline()),
    );
    expect(find.byType(AppBanner), findsNothing);
  });
}
