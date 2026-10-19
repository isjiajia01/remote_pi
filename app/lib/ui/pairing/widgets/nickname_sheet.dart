import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Post-pair nickname modal (plan/27 Wave A).
///
/// Asks the user for a friendly label for the just-paired PC. The
/// caller seeds [defaultName] with `pair_ok.hostname` when present
/// (e.g. "Mac do Jacob"), or the session name as a softer fallback,
/// or `null` so the field hints with the generic placeholder "Pi".
///
/// Returns the trimmed nickname string the user wants persisted:
/// - "Done" with non-empty input → returns the input.
/// - "Done" with empty input    → behaves as Skip (returns the default).
/// - "Skip"                     → returns [defaultName] ?? "Pi".
/// - Drag-down dismiss          → returns null (caller treats as Skip too).
///
/// Caller is responsible for calling `PeerRecord.copyWith(nickname:)`
/// and writing back to storage — the mesh-publish hook on
/// [PairingStorage] picks it up automatically.
Future<String?> showNicknameSheet(
  BuildContext context, {
  required String? defaultName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.surface,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _NicknameSheet(defaultName: defaultName),
  );
}

@visibleForTesting
class NicknameSheetForTest extends StatelessWidget {
  final String? defaultName;
  const NicknameSheetForTest({super.key, this.defaultName});

  @override
  Widget build(BuildContext context) =>
      _NicknameSheet(defaultName: defaultName);
}

class _NicknameSheet extends StatefulWidget {
  final String? defaultName;
  const _NicknameSheet({required this.defaultName});

  @override
  State<_NicknameSheet> createState() => _NicknameSheetState();
}

class _NicknameSheetState extends State<_NicknameSheet> {
  late final TextEditingController _controller;
  static const _fallback = 'Pi';

  String get _placeholder {
    final d = widget.defaultName?.trim();
    return (d == null || d.isEmpty) ? _fallback : d;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _placeholder);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final typed = _controller.text.trim();
    Navigator.of(context).pop(typed.isEmpty ? _placeholder : typed);
  }

  void _skip() {
    Navigator.of(context).pop(_placeholder);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Name this machine', style: context.typo.title2),
              const SizedBox(height: 6),
              Text(
                'Pick a label so this machine is easy to spot. You can change it later in Settings.',
                style: context.typo.footnote.copyWith(color: colors.ink2),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('nickname-sheet-field'),
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                style: context.typo.body,
                decoration: InputDecoration(
                  hintText: _placeholder,
                  hintStyle: TextStyle(color: colors.muted),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                key: const Key('nickname-sheet-save'),
                label: 'Done',
                onPressed: _save,
              ),
              SecondaryButton(
                key: const Key('nickname-sheet-skip'),
                label: 'Skip',
                onPressed: _skip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
