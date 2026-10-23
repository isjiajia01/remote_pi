import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/material.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({
    super.key,
    required this.onNext,
    required this.onReturning,
    this.onChangeRelay,
    this.relayHost = 'Community relay',
  });
  final VoidCallback onNext;
  final VoidCallback onReturning;
  final VoidCallback? onChangeRelay;
  final String relayHost;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/branding/perch-icon.png',
                      width: 100,
                      height: 100,
                      semanticLabel: 'Perch',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'perch',
                    style: brandTextStyle(
                      fontSize: 40,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Check in on your Pi agents',
                    textAlign: TextAlign.center,
                    style: context.typo.title2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'See every agent across your machines, read their work as it streams, and steer them from your phone.',
                    textAlign: TextAlign.center,
                    style: context.typo.body.copyWith(
                      color: context.colors.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Text(
          'Messages travel through a relay and are not end-to-end encrypted. The relay operator can read them.',
          style: context.typo.footnote.copyWith(color: context.colors.ink2),
          textAlign: TextAlign.center,
        ),
        TextButton(
          onPressed: onChangeRelay,
          child: Text('Relay: $relayHost · Change'),
        ),
        PrimaryButton(label: 'Pair your first Mac', onPressed: onNext),
        TextButton(
          onPressed: onReturning,
          child: Text(
            "I've used Perch before",
            style: context.typo.footnote.copyWith(color: context.colors.accent),
          ),
        ),
      ],
    ),
  );
}
