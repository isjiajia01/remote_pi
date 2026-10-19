import 'package:flutter/cupertino.dart';
import 'package:app/ui/core/themes/themes.dart';

enum AppButtonStyle { primary, secondary, destructive }

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onPressed: onPressed,
    style: AppButtonStyle.primary,
    fullWidth: fullWidth,
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AppButton(
    label: label,
    onPressed: onPressed,
    style: destructive ? AppButtonStyle.destructive : AppButtonStyle.secondary,
  );
}

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.style,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonStyle style;
  final bool fullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final primary = widget.style == AppButtonStyle.primary;
    final enabled = widget.onPressed != null;
    return Listener(
      onPointerDown: enabled ? (_) => _setPressed(true) : null,
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        opacity: !enabled
            ? .4
            : _pressed
            ? .85
            : 1,
        child: SizedBox(
          width: widget.fullWidth ? double.infinity : null,
          height: primary ? 50 : 44,
          child: CupertinoButton(
            onPressed: widget.onPressed,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: primary ? c.accent : null,
            disabledColor: primary ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(14),
            pressedOpacity: 1,
            child: Text(
              widget.label,
              style: context.typo.headline.copyWith(
                color: primary
                    ? c.onAccent
                    : widget.style == AppButtonStyle.destructive
                    ? c.error
                    : c.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
