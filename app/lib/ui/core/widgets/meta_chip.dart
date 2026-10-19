import 'package:flutter/widgets.dart';
import 'package:app/ui/core/themes/themes.dart';

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
    decoration: BoxDecoration(
      color: context.colors.surface2,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: context.typo.monoSmall),
  );
}
