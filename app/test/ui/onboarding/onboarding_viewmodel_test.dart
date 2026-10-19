import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStore implements FlutterSecureStorage {
  final values = <String, String>{};
  Completer<void>? writeGate;
  bool failWrites = false;
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await writeGate?.future;
    if (failWrites) throw StateError('storage unavailable');
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await writeGate?.future;
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Probe implements RelayReachability {
  RelayCheckResult result = const RelayCheckResult.reachable(
    Duration(milliseconds: 120),
  );
  Completer<RelayCheckResult>? pending;
  String? checkedUrl;
  @override
  Future<RelayCheckResult> check(String url) async {
    checkedUrl = url;
    return pending == null ? result : pending!.future;
  }
}

void main() {
  late _FakeStore store;
  late Preferences prefs;
  late _Probe probe;
  late OnboardingViewModel vm;
  OnboardingInProgress current() => vm.state as OnboardingInProgress;
  void custom(String url) {
    vm.next();
    vm.setRelayChoice(RelayChoice.custom);
    vm.setCustomRelayUrl(url);
  }

  setUp(() {
    store = _FakeStore();
    prefs = Preferences(store);
    probe = _Probe();
    vm = OnboardingViewModel(prefs, probe);
  });
  tearDown(() => vm.dispose());

  test('welcome, back, returning-user shortcut', () async {
    expect(current().step, OnboardingStep.welcome);
    await vm.next();
    expect(current().step, OnboardingStep.relay);
    vm.back();
    expect(current().step, OnboardingStep.welcome);
    vm.skipToPair();
    expect(current().step, OnboardingStep.pair);
    expect(resolveRelayUrl(prefs), kDefaultRelayUrl);
  });

  test(
    'custom relay is durable before pair opens, including continue anyway',
    () async {
      custom(' https://my-relay.example ');
      store.writeGate = Completer<void>();
      final leaving = vm.continueAnyway();
      await Future<void>.delayed(Duration.zero);
      expect(current().step, OnboardingStep.relay);
      expect(store.values['prefs.relay_url'], isNull);
      store.writeGate!.complete();
      await leaving;
      expect(current().step, OnboardingStep.pair);
      final restarted = Preferences(store);
      await restarted.load();
      expect(resolveRelayUrl(restarted), 'https://my-relay.example');
    },
  );

  test('failed save keeps relay step and retry writes durably', () async {
    custom('https://my-relay.example');
    store.failWrites = true;
    await vm.continueAnyway();
    expect(current().step, OnboardingStep.relay);
    expect(current().customRelayError, "Couldn't save the relay. Try again.");
    expect(prefs.relayUrl, isNull);
    store.failWrites = false;
    await vm.continueAnyway();
    expect(current().step, OnboardingStep.pair);
    final restarted = Preferences(store);
    await restarted.load();
    expect(restarted.relayUrl, 'https://my-relay.example');
  });

  test('community clears a previous override durably', () async {
    await prefs.setRelayUrl('https://old.example');
    await vm.next();
    await vm.continueAnyway();
    final restarted = Preferences(store);
    await restarted.load();
    expect(restarted.relayUrl, isNull);
    expect(current().step, OnboardingStep.pair);
  });

  test('invalid or empty custom URL never checks or advances', () async {
    custom('wss://wrong.example');
    await vm.checkAndContinue();
    expect(
      current().customRelayError,
      'Enter a full URL starting with https://',
    );
    expect(probe.checkedUrl, isNull);
    vm.setCustomRelayUrl('');
    await vm.continueAnyway();
    expect(current().step, OnboardingStep.relay);
  });

  test('success stays visible for 400ms, then persists and advances', () {
    fakeAsync((time) {
      custom('https://my-relay.example');
      vm.checkAndContinue();
      expect(current().relayCheck, RelayCheckStatus.checking);
      vm.setCustomRelayUrl('https://changed.example');
      time.flushMicrotasks();
      expect(probe.checkedUrl, 'https://my-relay.example');
      expect(current().relayCheck, RelayCheckStatus.reachable);
      expect(current().latencyMs, 120);
      time.elapse(const Duration(milliseconds: 399));
      expect(current().step, OnboardingStep.relay);
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
      expect(current().step, OnboardingStep.pair);
      expect(store.values['prefs.relay_url'], 'https://my-relay.example');
    });
  });

  test(
    'unreachable relay has specific copy and allows explicit bypass',
    () async {
      custom('https://offline.example');
      probe.result = const RelayCheckResult.failed(
        RelayCheckFailure.unreachable,
      );
      await vm.checkAndContinue();
      expect(
        current().customRelayError,
        "Can't reach this host. On Tailscale? Check the VPN is on.",
      );
      await vm.continueAnyway();
      expect(prefs.relayUrl, 'https://offline.example');
      expect(current().step, OnboardingStep.pair);
    },
  );

  test('check has an eight-second cap', () {
    fakeAsync((time) {
      vm.next();
      probe.pending = Completer<RelayCheckResult>();
      vm.checkAndContinue();
      time.elapse(const Duration(seconds: 8));
      time.flushMicrotasks();
      expect(current().customRelayError, 'No answer in 8 s.');
      expect(current().relayCheck, RelayCheckStatus.failed);
      probe.pending!.complete(
        const RelayCheckResult.reachable(Duration(seconds: 9)),
      );
      time.flushMicrotasks();
      expect(current().step, OnboardingStep.relay);
    });
  });

  test('complete and skip persist onboarding completion', () async {
    await vm.completePairing();
    expect(vm.state, isA<OnboardingComplete>());
    final restarted = Preferences(store);
    await restarted.load();
    expect(restarted.onboardingCompleted, isTrue);
  });
}
