import 'package:app/ui/pairing/states/pairing_error_copy.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const host = 'mac.tailnet.ts.net';
  final cases = <String, (String, String, String, String?)>{
    'relay_unreachable': (
      "Can't reach the relay",
      "$host didn't respond. Check your connection or Tailscale, or pick another relay.",
      'Try again',
      'Change relay',
    ),
    'pair_timeout': (
      "Your Mac didn't answer",
      'The relay is up but nothing replied in 30 s. Make sure Pi is open with /remote-pi running and uses the same relay ($host).',
      'Try again',
      'Change relay',
    ),
    'token_expired': (
      'Code expired',
      'Run /remote-pi pair again and scan the new code.',
      'Scan again',
      'Paste code',
    ),
    'token_consumed': (
      'Code already used',
      'Run /remote-pi pair again and scan the new code.',
      'Scan again',
      'Paste code',
    ),
    'token_unknown': (
      "Mac doesn't know this code",
      'Re-run /remote-pi pair on the Mac.',
      'Scan again',
      null,
    ),
    'invalid_code': (
      "That's not a Perch code",
      'Expected the code shown by /remote-pi pair.',
      'Scan again',
      'Paste code',
    ),
    'unexpected_response': ('Pairing failed', 'First line', 'Try again', null),
  };
  for (final entry in cases.entries) {
    test('${entry.key} maps to DESIGN error table', () {
      final copy = PairingErrorCopy.forError(
        PairingError(code: entry.key, message: 'First line\nRaw details'),
        host,
      );
      expect((
        copy.title,
        copy.body,
        copy.primary,
        copy.secondary,
      ), entry.value);
    });
  }
}
