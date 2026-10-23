import 'package:app/data/push/push_navigation.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import '../approvals/approval_service_test.dart' show flush;
import 'push_fakes.dart';

void main() {
  const machine = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  const other = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';
  const peer = PeerRecord(
    remoteEpk: machine,
    sessionName: 'Mac',
    relayUrl: 'https://local-pairing',
    pairedAt: 'today',
    roomId: 'old',
  );
  late PushStorage storage;
  late PushChannel channel;
  late ConnectionManager conn;
  late PushNavigation navigation;
  setUp(() {
    storage = PushStorage()..peers = [peer];
    channel = PushChannel()
      ..snapshotPeer = machine
      ..snapshot = [const RoomInfo(roomId: 'session-real', startedAt: 0)];
    conn = ConnectionManager(
      storage: storage,
      factory: (destination, _) async {
        expect(destination.relayUrl, 'https://local-pairing');
        return channel;
      },
    );
    navigation = PushNavigation(storage, conn);
  });
  tearDown(() {
    conn.dispose();
  });
  Map<String, dynamic> payload([String room = 'session-real']) => {
    'kind': 'session_finished',
    'machine_id': machine,
    'room_id': room,
    'url': 'https://never-connect-to-push-url',
  };
  test(
    'cold completion reconnects locally paired machine, requests fresh rooms and resolves exact room',
    () async {
      final result = await navigation.resolve(payload());
      expect(result, (peerEpk: machine, roomId: 'session-real'));
      expect(conn.activePeer!.remoteEpk, machine);
      expect(channel.requests.any((r) => r['type'] == 'rooms_check'), isTrue);
    },
  );
  test(
    'warm completion switches from another paired machine and prompt remains navigation only',
    () async {
      conn.adopt(
        PushChannel(),
        const PeerRecord(
          remoteEpk: other,
          sessionName: 'Other',
          relayUrl: 'https://other',
          pairedAt: 'today',
        ),
      );
      final result = await navigation.resolve({
        ...payload(),
        'kind': 'ui_prompt',
      });
      expect(result, (peerEpk: machine, roomId: 'session-real'));
      expect(channel.sent, isEmpty);
    },
  );
  test(
    'closed or renamed room, unknown pairing and generic payload fall back safely',
    () async {
      expect(await navigation.resolve(payload('old')), isNull);
      expect(
        await navigation.resolve({...payload(), 'machine_id': other}),
        isNull,
      );
      expect(await navigation.resolve({'kind': 'session_finished'}), isNull);
      expect(
        await navigation.resolve({...payload(), 'kind': 'approval_request'}),
        isNull,
      );
      expect(await navigation.resolve(payload('perch-control')), isNull);
      await flush();
    },
  );
  test(
    'fresh unchanged snapshot resolves and revoked local pairing never resolves',
    () async {
      expect(await navigation.resolve(payload()), isNotNull);
      expect(await navigation.resolve(payload()), isNotNull);
      storage.peers = [];
      expect(await navigation.resolve(payload()), isNull);
    },
  );
}
