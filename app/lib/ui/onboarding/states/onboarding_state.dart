// Sealed state for OnboardingViewModel. Switch exhaustively in
// OnboardingPage.build().

enum OnboardingStep { welcome, relay, pair }

enum RelayChoice { community, custom }

enum RelayCheckStatus { idle, checking, reachable, failed }

sealed class OnboardingState {
  const OnboardingState();
}

class OnboardingInProgress extends OnboardingState {
  final OnboardingStep step;
  final RelayChoice relayChoice;
  final String customRelayUrl;
  final String? customRelayError;
  final RelayCheckStatus relayCheck;
  final int? latencyMs;

  const OnboardingInProgress({
    this.step = OnboardingStep.welcome,
    this.relayChoice = RelayChoice.community,
    this.customRelayUrl = '',
    this.customRelayError,
    this.relayCheck = RelayCheckStatus.idle,
    this.latencyMs,
  });

  OnboardingInProgress copyWith({
    OnboardingStep? step,
    RelayChoice? relayChoice,
    String? customRelayUrl,
    String? customRelayError,
    bool clearCustomError = false,
    RelayCheckStatus? relayCheck,
    int? latencyMs,
  }) => OnboardingInProgress(
    step: step ?? this.step,
    relayCheck: relayCheck ?? this.relayCheck,
    latencyMs: latencyMs,
    relayChoice: relayChoice ?? this.relayChoice,
    customRelayUrl: customRelayUrl ?? this.customRelayUrl,
    customRelayError: clearCustomError
        ? null
        : (customRelayError ?? this.customRelayError),
  );

  @override
  bool operator ==(Object other) =>
      other is OnboardingInProgress &&
      other.step == step &&
      other.relayCheck == relayCheck &&
      other.latencyMs == latencyMs &&
      other.relayChoice == relayChoice &&
      other.customRelayUrl == customRelayUrl &&
      other.customRelayError == customRelayError;

  @override
  int get hashCode => Object.hash(
    step,
    relayChoice,
    customRelayUrl,
    customRelayError,
    relayCheck,
    latencyMs,
  );
}

class OnboardingComplete extends OnboardingState {
  const OnboardingComplete();
}
