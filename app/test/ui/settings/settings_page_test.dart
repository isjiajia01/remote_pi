import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/settings/relay_page.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Storage extends PairingStorage {
  _Storage(this.peers);
  List<PeerRecord> peers;

  @override
  Future<List<PeerRecord>> listPeers() async => List.of(peers);
  @override
  Future<void> savePeer(PeerRecord peer) async {
    peers = [peer, ...peers.where((p) => p.remoteEpk != peer.remoteEpk)];
  }

  @override
  Future<void> deletePeerSilent(String epk) async {
    peers.removeWhere((p) => p.remoteEpk == epk);
  }
}

class _Reachability implements RelayReachability {
  RelayCheckResult result = const RelayCheckResult.reachable(
    Duration(milliseconds: 120),
  );
  Completer<RelayCheckResult>? pending;
  final urls = <String>[];
  @override
  Future<RelayCheckResult> check(String url) async {
    urls.add(url);
    return pending?.future ?? result;
  }
}

class _Connection extends ConnectionManager {
  _Connection(PairingStorage storage)
    : super(
        storage: storage,
        factory: (_, _) => throw StateError('No network in UI tests'),
      );
  int boots = 0;
  @override
  Future<void> boot({String? preferredEpk}) async {
    boots++;
  }

  @override
  Future<void> disconnect() async {}
}

const _peer = PeerRecord(
  remoteEpk: 'epk',
  sessionName: 'mac-session',
  nickname: 'Studio Mac',
  pairedAt: '2026-10-12T00:00:00Z',
  relayUrl: 'https://legacy.example',
);

void main() {
  late Preferences prefs;
  late _Storage storage;
  late _Reachability reachability;
  late _Connection connection;
  late SettingsViewModel vm;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    prefs = Preferences();
    await prefs.setRelayUrl('https://onboarding.example');
    storage = _Storage([_peer]);
    reachability = _Reachability();
    connection = _Connection(storage);
    vm = SettingsViewModel(
      storage,
      prefs,
      connection,
      reachability,
      appVersion: '1.2.0',
      buildNumber: '8',
    );
  });

  tearDown(() {
    vm.dispose();
    connection.dispose();
    prefs.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: prefs),
          ChangeNotifierProvider.value(value: vm),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'machine rename and destructive confirmation use the grouped Settings flow',
    (tester) async {
      await pumpPage(tester, const SettingsPage());
      expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
      expect(find.text('MACHINES'), findsOneWidget);
      expect(find.text('Studio Mac'), findsOneWidget);
      expect(find.text('mac-session'), findsOneWidget);
      expect(find.textContaining('Paired 12 Oct'), findsOneWidget);
      expect(find.text('Pair a machine'), findsOneWidget);

      await tester.tap(find.text('Studio Mac'));
      await tester.pumpAndSettle();
      expect(find.text('Name this machine'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Office');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(storage.peers.single.nickname, 'Office');
      expect(find.text('Office'), findsOneWidget);

      final remove = find.bySemanticsLabel('Remove Office');
      final removeText = find.descendant(
        of: remove,
        matching: find.text('Remove'),
      );
      expect(removeText, findsOneWidget);
      expect(
        tester.widget<Text>(removeText).style!.color,
        tester.element(removeText).colors.error,
      );
      final button = find.ancestor(
        of: remove,
        matching: find.byType(CupertinoButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      await tester.tap(find.bySemanticsLabel('Remove Office'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('Remove Office?'), findsOneWidget);
      expect(
        find.text(
          'This phone will stop seeing its agents. You can pair again later.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(storage.peers, hasLength(1));
      await tester.tap(find.bySemanticsLabel('Remove Office'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(storage.peers, isEmpty);
      expect(find.text('Office'), findsNothing);
      expect(find.text('No machines yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings relay pushes the saved onboarding value into its editor',
    (tester) async {
      await pumpPage(tester, const SettingsPage());
      await tester.tap(find.text('onboarding.example'));
      await tester.pumpAndSettle();
      expect(find.byType(RelayPage), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!
            .text,
        prefs.relayUrl,
      );
      await tester.enterText(
        find.byType(CupertinoTextField),
        'https://new.example',
      );
      await tester.tap(find.text('Check & save'));
      await tester.pumpAndSettle();
      expect(prefs.relayUrl, 'https://new.example');
      expect(find.text('Saved · reachable 120 ms'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back').last);
      await tester.pumpAndSettle();
      expect(find.text('new.example'), findsOneWidget);
    },
  );

  testWidgets('relay errors stay inline and eight-second cap keeps old value', (
    tester,
  ) async {
    await pumpPage(tester, const RelayPage());
    await tester.enterText(find.byType(CupertinoTextField), 'bad');
    await tester.tap(find.text('Check & save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a full URL starting with https://'),
      findsOneWidget,
    );
    expect(prefs.relayUrl, 'https://onboarding.example');

    reachability.pending = Completer<RelayCheckResult>();
    await tester.enterText(
      find.byType(CupertinoTextField),
      'https://timeout.example',
    );
    await tester.tap(find.text('Check & save'));
    await tester.pump();
    expect(find.text('Checking relay…'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .enabled,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.text('No answer in 8 s.'), findsOneWidget);
    expect(prefs.relayUrl, 'https://onboarding.example');
    reachability.pending!.complete(
      const RelayCheckResult.failed(RelayCheckFailure.unreachable),
    );
    await tester.pumpAndSettle();
    reachability.pending = null;
    await tester.tap(find.text('Use community relay'));
    await tester.pumpAndSettle();
    expect(prefs.relayUrl, isNull);
    expect(vm.effectiveRelayUrl, kDefaultRelayUrl);
    expect(find.text('Saved · reachable 120 ms'), findsOneWidget);
  });

  testWidgets(
    'Appearance uses persisted Cupertino segments and About shows version and iOS updates',
    (tester) async {
      await pumpPage(tester, const SettingsPage());
      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(prefs.themeMode, ThemeMode.dark);
      await tester.ensureVisible(find.text('XL'));
      await tester.tap(find.text('XL'));
      await tester.pumpAndSettle();
      expect(prefs.fontScale, AppFontScale.extraLarge);
      await tester.ensureVisible(find.text('Version 1.2.0 (8)'));
      expect(
        find.text('Updates come from TestFlight / the App Store'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Licenses'));
      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
