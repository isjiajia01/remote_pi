import 'dart:convert';
import 'dart:io';

import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../.orchestration/contracts/perch-v1/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test(
    'shared capabilities golden encodes and decodes exact wire contract',
    () {
      final golden = fixture('capabilities');
      final request = golden['request'] as Map<String, dynamic>;
      expect(
        jsonDecode(
          encodeClient(PerchCapabilitiesGet(id: request['id'] as String)),
        ),
        request,
      );
      final response =
          decodeServer(jsonEncode(golden['response']))
              as PerchCapabilitiesResult;
      expect(response.id, 'cap-1');
      expect(response.supportsTimeline, isTrue);
      expect(response.ackSemantics, 'delivery_only');
      expect(response.limits, {
        'retention': 512,
        'max_events': 128,
        'max_wait_ms': 25000,
        'max_subscribers': 8,
      });
    },
  );
  for (final name in ['agents-list', 'agents-events', 'replay-gap']) {
    test('shared $name golden request and response', () {
      final golden = fixture(name);
      final request = golden['request'] as Map<String, dynamic>;
      final encoded = encodeClient(
        PerchRequest(
          id: request['id'] as String,
          method: request['method'] as String,
          params: request['params'] as Map<String, dynamic>,
        ),
      );
      expect(jsonDecode(encoded), request);
      final response =
          decodeServer(jsonEncode(golden['response'])) as PerchResult;
      expect(response.id, request['id']);
      expect(response.method, request['method']);
      expect(response.result, (golden['response'] as Map)['result']);
      if (name == 'agents-list') {
        expect(response.snapshot.revision, 1);
        expect(response.snapshot.cursor, 1);
        expect(response.snapshot.epoch, 'broker-epoch-1');
        expect(response.snapshot.agents.single.address, '/work/perch@planner');
      } else if (name == 'agents-events') {
        final event = response.eventPage.events.single;
        expect(event.id, '0199a000-0000-7000-8000-000000000001');
        expect(event.re, '0199a000-0000-7000-8000-000000000000');
        expect(event.cursor, 2);
        expect(event.ts.millisecondsSinceEpoch, 1792368000000);
        expect(event.actor, '/work/perch@planner');
        expect(event.target, '/work/perch@coder');
        expect(event.delivered, ['/work/perch@coder']);
        expect(event.via, 'uds');
        expect(event.verb, 'delivered');
        expect(event.verb, isNot(contains('done')));
      } else {
        expect(response.eventPage.resyncRequired, isTrue);
        expect(response.eventPage.events, isEmpty);
        expect(response.eventPage.cursor, 513);
      }
    });
  }
  test(
    'all shared error golden codes decode without legacy error conversion',
    () {
      final errors =
          jsonDecode(
                File(
                  '../.orchestration/contracts/perch-v1/errors.json',
                ).readAsStringSync(),
              )
              as List;
      expect(errors.length, 7);
      for (final raw in errors) {
        final error = decodeServer(jsonEncode(raw)) as PerchError;
        expect(error.id, 'error-1');
        expect(error.code, raw['error']['code']);
        expect(error.message, 'Perch read failed');
      }
    },
  );
  test('foreign scope and version are rejected', () {
    final golden = fixture('agents-list')['response'] as Map<String, dynamic>;
    expect(
      () => decodeServer(jsonEncode({...golden, 'version': 2})),
      throwsFormatException,
    );
    expect(
      () => decodeServer(
        jsonEncode({
          ...golden,
          'result': {
            ...(golden['result'] as Map<String, dynamic>),
            'scope': 'global',
          },
        }),
      ),
      throwsFormatException,
    );
  });
}
