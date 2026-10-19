import 'package:app/ui/pairing/pairing_page.dart';
import 'package:flutter/material.dart';

class PairStep extends StatelessWidget {
  const PairStep({
    super.key,
    required this.onPaired,
    required this.onBack,
    required this.onSkip,
  });
  final VoidCallback onPaired;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) =>
      PairingFlow(onPaired: onPaired, onChangeRelay: onBack, onSkip: onSkip);
}
