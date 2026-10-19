import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/material.dart';

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({
    super.key,
    required this.onNext,
    required this.onReturning,
  });
  final VoidCallback onNext;
  final VoidCallback onReturning;

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
                  SizedBox(
                    height: 28,
                    width: 28,
                    child: Stack(
                      children: [
                        Positioned(
                          bottom: 4,
                          child: Container(
                            width: 28,
                            height: 2,
                            color: context.colors.ink,
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 8,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: context.colors.working,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'perch',
                    style: brandTextStyle(
                      fontSize: 40,
                      color: context.colors.ink,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Watch over your Pi agents',
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
        PrimaryButton(label: 'Get started', onPressed: onNext),
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
