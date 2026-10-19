import 'pairing_state.dart';

class PairingErrorCopy {
  const PairingErrorCopy(this.title, this.body, this.primary, [this.secondary]);
  final String title;
  final String body;
  final String primary;
  final String? secondary;

  factory PairingErrorCopy.forError(
    PairingError error,
    String host,
  ) => switch (error.code) {
    'relay_unreachable' => PairingErrorCopy(
      "Can't reach the relay",
      "$host didn't respond. Check your connection or Tailscale, or pick another relay.",
      'Try again',
      'Change relay',
    ),
    'pair_timeout' => PairingErrorCopy(
      "Your Mac didn't answer",
      'The relay is up but nothing replied in 30 s. Make sure Pi is open with /remote-pi running and uses the same relay ($host).',
      'Try again',
      'Change relay',
    ),
    'token_expired' => const PairingErrorCopy(
      'Code expired',
      'Run /remote-pi pair again and scan the new code.',
      'Scan again',
      'Paste code',
    ),
    'token_consumed' => const PairingErrorCopy(
      'Code already used',
      'Run /remote-pi pair again and scan the new code.',
      'Scan again',
      'Paste code',
    ),
    'token_unknown' => const PairingErrorCopy(
      "Mac doesn't know this code",
      'Re-run /remote-pi pair on the Mac.',
      'Scan again',
    ),
    'invalid_code' => const PairingErrorCopy(
      "That's not a Perch code",
      'Expected the code shown by /remote-pi pair.',
      'Scan again',
      'Paste code',
    ),
    _ => PairingErrorCopy(
      'Pairing failed',
      error.message.isEmpty ? error.code : error.message.split('\n').first,
      'Try again',
    ),
  };
}
