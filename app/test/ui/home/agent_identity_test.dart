import 'package:app/protocol/protocol.dart';
import 'package:app/ui/home/states/agent_identity.dart';
import 'package:flutter_test/flutter_test.dart';

const uuid = '000f7ed8-04b8-4d2a-9c1e-1234567890ab';

RoomInfo room(String id, {String? name, String cwd = '/u/10.15_Perch'}) =>
    RoomInfo(roomId: id, name: name, cwd: cwd, startedAt: 1);

void main() {
  test('room kind comes from the room id; legacy ids are terminal', () {
    expect(roomKindOf('AbC-12_xyz34').origin, RoomOrigin.terminal);
    expect(roomKindOf('main').origin, RoomOrigin.terminal);
    final phone = roomKindOf('session-$uuid');
    expect(phone.origin, RoomOrigin.phone);
    expect(phone.phoneSessionId, uuid);
    expect(roomKindOf('session-not-a-uuid').origin, RoomOrigin.terminal);
    final sub = roomKindOf('sub.h4sh12345678.AbC-12_xyz34');
    expect(sub.origin, RoomOrigin.subagent);
    expect(sub.parentRoomId, 'AbC-12_xyz34');
    expect(
      roomKindOf('sub.h4sh12345678.session-$uuid').parentRoomId,
      'session-$uuid',
    );
    expect(roomKindOf('sub.h4sh12345678').parentRoomId, isNull);
  });

  test('titles: generated names collapse to origin, custom names win', () {
    expect(sessionTitle(room('a', name: '10.15_Perch')), 'Terminal');
    expect(sessionTitle(room('a')), 'Terminal');
    expect(sessionTitle(room('a', name: '10.15_Perch#3')), 'Terminal 3');
    expect(sessionTitle(room('a', name: 'reviewer')), 'reviewer');
    expect(
      sessionTitle(room('session-$uuid', name: '10.15_Perch-$uuid')),
      'Phone session · 000f',
    );
    expect(sessionTitle(room('session-$uuid', name: 'Fix login')), 'Fix login');
    expect(
      sessionTitle(room('sub.h4sh12345678.x', name: '10.15_Perch#3')),
      'Sub-agent 3',
    );
  });

  test('model labels: one form per model, tiers read as words', () {
    expect(friendlyModel('group/std'), ('Standard', false));
    expect(friendlyModel('anthropic/claude-sonnet-4-5-20250929'), (
      'sonnet-4-5',
      true,
    ));
    expect(friendlyModel('group/model-claude-opus'), ('opus', true));
    expect(friendlyModel('Claude Opus · 5.5'), ('Claude Opus · 5.5', false));
    expect(friendlyModel('标准'), ('标准', false));
    expect(friendlyModel('  '), ('', false));
  });
}
