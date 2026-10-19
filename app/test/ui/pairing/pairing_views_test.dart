import 'package:app/ui/core/themes/app_theme.dart';
import 'package:app/ui/pairing/pairing_page.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'error and connecting fit ${dark ? 'dark' : 'light'} at large text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget wrap(Widget child) => MaterialApp(
          theme: dark ? buildDarkTheme() : buildLightTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        );
        for (final code in [
          'relay_unreachable',
          'pair_timeout',
          'token_expired',
          'token_consumed',
          'token_unknown',
          'invalid_code',
          'other',
        ]) {
          await tester.pumpWidget(
            wrap(
              PairingErrorView(
                error: PairingError(
                  code: code,
                  message: 'Raw details\nSecond line',
                ),
                host: 'mac.tailnet.ts.net',
                onRetry: () {},
                onPaste: () {},
                onChangeRelay: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: code);
          expect(find.text('Details'), findsOneWidget);
        }
        await tester.pumpWidget(
          wrap(
            PairingConnectingView(
              state: PairingConnecting(
                sessionName: 'MacBook Pro',
                stage: PairingStage.waitingForMac,
                startedAt: DateTime.now(),
              ),
              host: 'mac.tailnet.ts.net',
              onCancel: () {},
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Waiting for MacBook Pro to answer'), findsOneWidget);
        expect(find.text('Confirming pairing'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
