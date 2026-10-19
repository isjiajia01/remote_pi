import 'dart:async';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/relay_reachability.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';

class OnboardingViewModel extends ViewModel<OnboardingState> {
  OnboardingViewModel(this._prefs, this._reachability)
    : super(
        OnboardingInProgress(
          relayChoice: _prefs.relayUrl == null
              ? RelayChoice.community
              : RelayChoice.custom,
          customRelayUrl: _prefs.relayUrl ?? '',
        ),
      );

  final Preferences _prefs;
  final RelayReachability _reachability;
  bool _disposed = false;
  bool _saving = false;

  String get relayUrl {
    final s = state;
    if (s is! OnboardingInProgress) return resolveRelayUrl(_prefs);
    return s.relayChoice == RelayChoice.community
        ? kDefaultRelayUrl
        : s.customRelayUrl.trim();
  }

  Future<void> next() async {
    final s = state;
    if (s is! OnboardingInProgress || _busy(s)) return;
    switch (s.step) {
      case OnboardingStep.welcome:
        emit(s.copyWith(step: OnboardingStep.relay));
      case OnboardingStep.relay:
        await checkAndContinue();
      case OnboardingStep.pair:
        break;
    }
  }

  bool _busy(OnboardingInProgress s) =>
      _saving ||
      s.relayCheck == RelayCheckStatus.checking ||
      s.relayCheck == RelayCheckStatus.reachable;

  bool _validate(OnboardingInProgress s) {
    if (s.relayChoice == RelayChoice.custom &&
        !isValidRelayUrl(s.customRelayUrl.trim())) {
      emit(
        s.copyWith(
          customRelayError: 'Enter a full URL starting with https://',
          relayCheck: RelayCheckStatus.failed,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> checkAndContinue() async {
    final s = state;
    if (s is! OnboardingInProgress ||
        s.step != OnboardingStep.relay ||
        _busy(s) ||
        !_validate(s)) {
      return;
    }
    emit(
      s.copyWith(relayCheck: RelayCheckStatus.checking, clearCustomError: true),
    );
    final result = await _reachability
        .check(relayUrl)
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () =>
              const RelayCheckResult.failed(RelayCheckFailure.timeout),
        );
    if (_disposed) return;
    if (result.failure != null) {
      emit(
        s.copyWith(
          relayCheck: RelayCheckStatus.failed,
          customRelayError: result.failure == RelayCheckFailure.timeout
              ? 'No answer in 8 s.'
              : "Can't reach this host. On Tailscale? Check the VPN is on.",
        ),
      );
      return;
    }
    emit(
      s.copyWith(
        relayCheck: RelayCheckStatus.reachable,
        latencyMs: result.elapsed!.inMilliseconds,
        clearCustomError: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!_disposed) await _persistRelay(s);
  }

  Future<void> continueAnyway() async {
    final s = state;
    if (s is! OnboardingInProgress ||
        s.step != OnboardingStep.relay ||
        _busy(s) ||
        !_validate(s)) {
      return;
    }
    await _persistRelay(s);
  }

  Future<void> _persistRelay(OnboardingInProgress s) async {
    _saving = true;
    try {
      await _prefs.setRelayUrl(
        s.relayChoice == RelayChoice.custom ? s.customRelayUrl.trim() : null,
      );
      if (!_disposed) {
        emit(
          s.copyWith(
            step: OnboardingStep.pair,
            relayCheck: RelayCheckStatus.idle,
            clearCustomError: true,
          ),
        );
      }
    } catch (_) {
      if (!_disposed) {
        emit(
          s.copyWith(
            relayCheck: RelayCheckStatus.failed,
            customRelayError: "Couldn't save the relay. Try again.",
          ),
        );
      }
    } finally {
      _saving = false;
    }
  }

  void skipToPair() {
    final s = state;
    if (s is OnboardingInProgress) emit(s.copyWith(step: OnboardingStep.pair));
  }

  void back() {
    final s = state;
    if (s is! OnboardingInProgress || _busy(s)) return;
    if (s.step != OnboardingStep.welcome) {
      emit(
        s.copyWith(
          step: OnboardingStep.values[s.step.index - 1],
          relayCheck: RelayCheckStatus.idle,
          clearCustomError: true,
        ),
      );
    }
  }

  void setRelayChoice(RelayChoice choice) {
    final s = state;
    if (s is! OnboardingInProgress || _busy(s)) return;
    emit(
      s.copyWith(
        relayChoice: choice,
        relayCheck: RelayCheckStatus.idle,
        clearCustomError: true,
      ),
    );
  }

  void setCustomRelayUrl(String url) {
    final s = state;
    if (s is! OnboardingInProgress || _busy(s)) return;
    emit(
      s.copyWith(
        customRelayUrl: url,
        relayCheck: RelayCheckStatus.idle,
        clearCustomError: true,
      ),
    );
  }

  Future<void> completePairing() async {
    await _prefs.setOnboardingCompleted(true);
    if (!_disposed) emit(const OnboardingComplete());
  }

  Future<void> skipPairing() => completePairing();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
