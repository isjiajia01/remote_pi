import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/widgets.dart';

class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});
  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, child) => Opacity(
      opacity: MediaQuery.disableAnimationsOf(context)
          ? 1
          : .55 + .45 * (1 - (2 * _pulse.value - 1).abs()),
      child: child,
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              key: ValueKey('home-skeleton-$i'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(context, 10, 10),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _block(context, 148, 18),
                        const SizedBox(height: 8),
                        _block(context, 208, 12),
                        const SizedBox(height: 8),
                        _block(context, 100, 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  Widget _block(BuildContext context, double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.colors.surface2,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}
