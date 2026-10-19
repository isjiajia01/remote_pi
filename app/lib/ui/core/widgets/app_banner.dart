import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:app/ui/core/themes/themes.dart';

enum BannerVariant { neutral, error }

/// Inline persistent condition, placed below navigation by the caller.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.variant = BannerVariant.neutral,
    this.actionLabel,
    this.onAction,
    this.visible = true,
  }) : assert((actionLabel == null) == (onAction == null));

  final String message;
  final BannerVariant variant;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final error = variant == BannerVariant.error;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 150 : 250),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      child: !visible
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey((message, variant)),
              liveRegion: true,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: error ? c.errorSoft : c.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      error ? LucideIcons.circleAlert : LucideIcons.info,
                      size: 18,
                      color: error ? c.error : c.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.footnote.copyWith(
                          color: error ? c.error : c.ink,
                        ),
                      ),
                    ),
                    if (actionLabel != null)
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 8),
                        onPressed: onAction,
                        child: Text(
                          actionLabel!,
                          style: context.typo.footnote.copyWith(
                            color: c.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
