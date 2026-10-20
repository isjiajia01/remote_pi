import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/approval_digest.dart';
import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> shared(String name) =>
    jsonDecode(
          File(
            '../.orchestration/contracts/perch-v1/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test(
    'extension approval fixture digest and exact decision binding',
    () async {
      final golden = shared('tool-approval');
      final request =
          decodeServer(jsonEncode(golden['request']))
              as PerchToolApprovalRequest;
      expect(await approvalArgsDigest(request.args), request.argsDigest);
      expect(
        jsonDecode(
          encodeClient(
            PerchToolApprovalDecision(
              request: request,
              decision: PerchApprovalDecision.allow,
            ),
          ),
        ),
        golden['decision'],
      );
      expect(request.isExpired(request.expiresAt), isTrue);
      expect(
        request.isExpired(
          request.expiresAt.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
      expect(() => request.args['nested'] = null, throwsUnsupportedError);
      expect(
        () => (request.args['nested'] as Map)['value'] = 2,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'Node fixture sorts non-ASCII keys by UTF-16 units and matches number encoding',
    () async {
      final golden =
          jsonDecode(
                File(
                  'test/fixtures/approval_non_ascii.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(canonicalApprovalArgs(golden['args']), golden['canonical']);
      expect(await approvalArgsDigest(golden['args']), golden['args_digest']);
      expect(canonicalApprovalArgs({'n': 1.0}), '{"n":1}');
      expect(() => canonicalApprovalArgs(double.nan), throwsFormatException);
    },
  );
  test('approval rejects foreign version and malformed binding', () {
    final request = shared('tool-approval')['request'] as Map<String, dynamic>;
    for (final patch in [
      {'version': 2},
      {'owner': ''},
      {'args_digest': 'bad'},
      {'expires_at': 'soon'},
    ]) {
      expect(
        () => decodeServer(jsonEncode({...request, ...patch})),
        throwsFormatException,
      );
    }
  });
  test('extension push registration/unregistration fixtures and response', () {
    final golden = shared('push');
    for (final name in ['register', 'unregister']) {
      final entry = golden[name] as Map;
      final request = entry['request'] as Map;
      expect(
        jsonDecode(
          encodeClient(
            PerchPushRegister(
              id: request['id'] as String,
              owner: request['owner'] as String,
              token: request['token'] as String,
              environment: PerchPushEnvironment.sandbox,
              unregister: name == 'unregister',
            ),
          ),
        ),
        request,
      );
      final result =
          decodeServer(jsonEncode(entry['response'])) as PerchPushResult;
      expect(result.registered, name == 'register');
      expect(result.id, request['id']);
    }
  });
}
