import 'package:app/data/transport/relay_config.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RelayStep extends StatefulWidget {
  const RelayStep({
    super.key,
    required this.state,
    required this.onChoice,
    required this.onCustomUrl,
    required this.onBack,
    required this.onNext,
    required this.onContinueAnyway,
  });
  final OnboardingInProgress state;
  final ValueChanged<RelayChoice> onChoice;
  final ValueChanged<String> onCustomUrl;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onContinueAnyway;

  @override
  State<RelayStep> createState() => _RelayStepState();
}

class _RelayStepState extends State<RelayStep> {
  late final _controller = TextEditingController(
    text: widget.state.customRelayUrl,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final busy =
        s.relayCheck == RelayCheckStatus.checking ||
        s.relayCheck == RelayCheckStatus.reachable;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 24),
                Text('Choose a relay', style: context.typo.title2),
                const SizedBox(height: 8),
                Text(
                  'Your phone and your Mac meet through a relay. Messages pass through it.',
                  style: context.typo.footnote.copyWith(
                    color: context.colors.ink2,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _choice(
                        context,
                        RelayChoice.community,
                        'Community relay',
                        Uri.parse(kDefaultRelayUrl).host,
                        busy,
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        color: context.colors.hairline,
                      ),
                      _choice(
                        context,
                        RelayChoice.custom,
                        'My own relay',
                        'Self-hosted or Tailscale URL',
                        busy,
                      ),
                      if (s.relayChoice == RelayChoice.custom)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextField(
                            controller: _controller,
                            enabled: !busy,
                            onChanged: widget.onCustomUrl,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            style: context.typo.mono,
                            decoration: InputDecoration(
                              hintText: 'https://host.tailnet.ts.net',
                              hintStyle: context.typo.mono.copyWith(
                                color: context.colors.ink2,
                              ),
                              filled: true,
                              fillColor: context.colors.surface2,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (s.customRelayError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.circleAlert,
                          color: context.colors.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.customRelayError!,
                            style: context.typo.footnote.copyWith(
                              color: context.colors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (s.relayCheck == RelayCheckStatus.reachable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.check,
                    color: context.colors.online,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reachable · ${s.latencyMs} ms',
                    style: context.typo.footnote.copyWith(
                      color: context.colors.online,
                    ),
                  ),
                ],
              ),
            ),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              PrimaryButton(
                label: s.relayCheck == RelayCheckStatus.checking
                    ? 'Checking relay…'
                    : 'Check & continue',
                onPressed: busy ? null : widget.onNext,
              ),
              if (s.relayCheck == RelayCheckStatus.checking)
                Positioned(
                  left: 16,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.onAccent,
                    ),
                  ),
                ),
            ],
          ),
          if (s.relayCheck == RelayCheckStatus.failed)
            SecondaryButton(
              label: 'Continue anyway',
              onPressed: widget.onContinueAnyway,
            ),
          SecondaryButton(
            label: 'Back',
            onPressed: busy ? null : widget.onBack,
          ),
        ],
      ),
    );
  }

  Widget _choice(
    BuildContext context,
    RelayChoice choice,
    String title,
    String subtitle,
    bool busy,
  ) {
    final selected = widget.state.relayChoice == choice;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: busy ? null : () => widget.onChoice(choice),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 20,
                  color: selected ? context.colors.accent : context.colors.ink3,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.typo.body),
                      Text(
                        subtitle,
                        style: choice == RelayChoice.community
                            ? context.typo.monoSmall
                            : context.typo.footnote.copyWith(
                                color: context.colors.ink2,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
