import 'package:app/routing/adaptive.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/onboarding/widgets/widgets.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _syncPage(OnboardingStep step) {
    final target = step.index.toDouble();
    if (!_pageController.hasClients) return;
    final current = _pageController.page ?? 0;
    if ((current - target).abs() < 0.01) return;
    _pageController.animateToPage(
      step.index,
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250,
      ),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OnboardingViewModel>();
    final state = vm.state;

    if (state is OnboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final paired = context.read<PairingViewModel>().state;
        context.go(
          '/home',
          extra: paired is PairingPaired
              ? {'pairedPeerEpk': paired.peer.remoteEpk}
              : null,
        );
      });
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: const SizedBox.shrink(),
      );
    }

    final s = state as OnboardingInProgress;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPage(s.step);
    });

    return Scaffold(
      backgroundColor: context.colors.bg,
      // Plan/tablet — cap + centre the stepper on wide screens so the
      // phone-oriented column doesn't stretch edge-to-edge on iPad.
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              _StepIndicator(step: s.step),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    WelcomeStep(onNext: vm.next, onReturning: vm.skipToPair),
                    RelayStep(
                      state: s,
                      onChoice: vm.setRelayChoice,
                      onCustomUrl: vm.setCustomRelayUrl,
                      onBack: vm.back,
                      onNext: vm.checkAndContinue,
                      onContinueAnyway: vm.continueAnyway,
                    ),
                    if (s.step == OnboardingStep.pair)
                      PairStep(
                        onPaired: () {
                          // ignore: unawaited_futures
                          vm.completePairing();
                        },
                        onBack: vm.back,
                        onSkip: () {
                          // ignore: unawaited_futures
                          vm.skipPairing();
                        },
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final OnboardingStep step;
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: List.generate(OnboardingStep.values.length, (i) {
          final active = i <= step.index;
          return Expanded(
            child: AnimatedContainer(
              duration: Duration(
                milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250,
              ),
              curve: Curves.easeInOutCubic,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 3,
                right: i == OnboardingStep.values.length - 1 ? 0 : 3,
              ),
              height: 4,
              decoration: BoxDecoration(
                color: active ? colors.accent : colors.border,
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
            ),
          );
        }),
      ),
    );
  }
}
