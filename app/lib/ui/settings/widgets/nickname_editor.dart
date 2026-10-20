import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Bottom sheet to edit (or clear) a peer's local nickname.
///
/// Returns:
///  - a non-empty `String` when the user tapped **Save** with a value
///  - `''` (empty) when the user tapped **Remove nickname**
///  - `null` when the sheet was dismissed / canceled
Future<String?> showNicknameEditor(
  BuildContext context, {
  required String defaultName,
  String currentNickname = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _NicknameEditorSheet(
        currentNickname: currentNickname,
        defaultName: defaultName,
      ),
    ),
  );
}

class _NicknameEditorSheet extends StatefulWidget {
  final String currentNickname;
  final String defaultName;
  const _NicknameEditorSheet({
    required this.currentNickname,
    required this.defaultName,
  });

  @override
  State<_NicknameEditorSheet> createState() => _NicknameEditorSheetState();
}

class _NicknameEditorSheetState extends State<_NicknameEditorSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentNickname);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = _ctrl.text.trim();
    Navigator.of(context).pop(value);
  }

  void _remove() {
    Navigator.of(context).pop('');
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasCurrent = widget.currentNickname.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text('Name this machine', style: context.typo.title2),
          const SizedBox(height: 4),
          Text(
            'Local only — the Mac is not notified.',
            style: context.typo.footnote,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 40,
            style: context.typo.body,
            cursorColor: colors.accent,
            decoration: InputDecoration(
              labelText: 'Nickname',
              labelStyle: context.typo.footnote,
              helperText: 'Default: ${widget.defaultName}',
              helperStyle: context.typo.footnote,
              counterStyle: context.typo.footnote,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          if (hasCurrent) ...[
            TextButton.icon(
              onPressed: _remove,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('Remove nickname'),
            ),
            const SizedBox(height: 4),
          ],
          PrimaryButton(label: 'Save', onPressed: _save),
          SecondaryButton(label: 'Cancel', onPressed: _cancel),
        ],
      ),
    );
  }
}
