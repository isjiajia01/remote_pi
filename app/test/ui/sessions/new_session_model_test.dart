import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/control_client.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/sessions/new_session_model.dart';
import 'package:flutter_test/flutter_test.dart';

const mac = PeerRecord(
  remoteEpk: 'mac',
  sessionName: 'Mac',
  relayUrl: 'ws://x',
  pairedAt: 'today',
);
const other = PeerRecord(
  remoteEpk: 'other',
  sessionName: 'Other',
  relayUrl: 'ws://x',
  pairedAt: 'today',
);

class MemoryStore extends PendingSessionStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic>? next) async {
    value = next;
  }
}

class Channel extends Fake implements IChannel {}

class Connection extends Fake implements ConnectionManager {
  PeerRecord? selected = other;
  bool live = false;
  @override
  PeerRecord? get activePeer => selected;
  @override
  IChannel? get channel => Channel();
  @override
  Future<void> switchTo(PeerRecord peer) async {
    selected = peer;
  }

  @override
  bool isRoomLive(String epk, String room) =>
      live && epk == 'mac' && room == 'session-new';
}

class Client extends ControlClient {
  Client(this.connection, this.store);
  final Connection connection;
  final MemoryStore store;
  bool timeoutCreate = false;
  bool deletedDirectory = false;
  String state = 'failed';
  final calls = <ControlAction>[];
  @override
  String get connectionKey => 'test';
  @override
  String get machineLabel => 'Mac';
  @override
  Stream<void> get connections => const Stream.empty();
  @override
  Future<ControlCapabilities> capabilities() async => ControlCapabilities([
    'directories.roots',
    'directories.list',
    'sessions.create',
    'sessions.get',
    'sessions.stop',
  ]);
  @override
  ControlAction action(
    String method,
    Map<String, dynamic> params,
    int? revision,
  ) => ControlAction('unused', method, params, revision);
  @override
  Future<ControlReply> execute(ControlAction action) async {
    expect(
      connection.activePeer,
      mac,
      reason: 'must target selected machine, not previous active peer',
    );
    expect(action.revision, isNull);
    calls.add(action);
    switch (action.method) {
      case 'directories.roots':
        return ControlReply(0, {
          'roots': [
            {'id': 'life', 'name': 'Life-OS'},
          ],
        });
      case 'directories.list':
        return ControlReply(0, {
          'directories': [
            {'name': '中文 Project', 'relative_path': '中文 Project'},
          ],
          'next_offset': null,
        });
      case 'sessions.create':
        expect(
          store.value?['id'],
          action.id,
          reason: 'persist before dispatch',
        );
        if (deletedDirectory) {
          throw const ControlFailure(
            'invalid_argument',
            'Directory is unavailable',
          );
        }
        if (timeoutCreate) throw const ControlFailure('timeout', 'unknown');
        return ControlReply(0, {
          'session_id': 'new',
          'room_id': 'session-new',
          'name': 'Project-new',
          'state': state,
        });
      case 'sessions.stop':
        return ControlReply(0, {'state': 'stopped'});
      default:
        throw StateError(action.method);
    }
  }
}

void main() {
  late MemoryStore store;
  late Connection conn;
  late Client client;
  late NewSessionModel model;
  setUp(() {
    store = MemoryStore();
    conn = Connection();
    client = Client(conn, store);
    model = NewSessionModel(conn, client, store);
  });
  tearDown(() => model.dispose());
  test(
    'zero rooms: selects machine, browses Unicode path and creates fresh request',
    () async {
      await model.initialize([mac, other]);
      await model.selectPeer(mac);
      await model.browse('中文 Project');
      await model.create();
      expect(model.ready, isFalse);
      expect(model.session?['state'], 'failed');
      expect(client.calls.last.params['relative_path'], '中文 Project');
      await model.resolveTerminal();
      await model.create();
      final ids = client.calls
          .where((a) => a.method == 'sessions.create')
          .map((a) => a.id)
          .toList();
      expect(
        ids.toSet().length,
        2,
        reason: 'deliberate second create is independent',
      );
    },
  );
  test(
    'timeout and page reconstruction reuse saved request and machine',
    () async {
      await model.initialize([mac, other]);
      await model.selectPeer(mac);
      client.timeoutCreate = true;
      await model.create();
      final id = store.value!['id'];
      expect(model.hasPending, isTrue);
      final recovered = NewSessionModel(conn, client, store);
      addTearDown(recovered.dispose);
      client.timeoutCreate = false;
      client.state = 'running';
      conn.live = true;
      conn.selected = other;
      await recovered.initialize([mac, other]);
      expect(recovered.ready, isTrue);
      expect(recovered.peer, mac);
      expect(
        client.calls
            .where((a) => a.method == 'sessions.create')
            .every((a) => a.id == id),
        isTrue,
      );
      await recovered.completeOpening();
      expect(store.value, isNull);
    },
  );
  test(
    'failed process does not open an old online room; stopping resolves request',
    () async {
      await model.initialize([mac]);
      await model.selectPeer(mac);
      await model.create();
      expect(model.ready, isFalse);
      expect(model.error, contains('failed'));
      await model.stop();
      expect(model.hasPending, isFalse);
    },
  );
  test(
    'deleted directory rejection releases pending and allows folder reselection',
    () async {
      await model.initialize([mac]);
      await model.selectPeer(mac);
      await model.browse('deleted');
      client.deletedDirectory = true;
      await model.create();
      expect(model.error, contains('unavailable'));
      expect(store.value, isNull);
      expect(model.hasPending, isFalse);
      expect(model.root, isNull);
      client.deletedDirectory = false;
      await model.selectPeer(mac);
      conn.live = true;
      client.state = 'running';
      await model.create();
      expect(model.ready, isTrue);
    },
  );
  test(
    'interrupted pending can be released after explicit local cleanup acknowledgement',
    () async {
      store.value = {
        'peer': 'mac',
        'id': 'interrupted-request',
        'root_id': 'life',
        'relative_path': '',
      };
      client.state = 'interrupted';
      await model.initialize([mac]);
      expect(model.hasPending, isTrue);
      expect(model.ready, isFalse);
      await model.acknowledgeInterrupted();
      expect(store.value, isNull);
      expect(model.hasPending, isFalse);
      expect(client.calls.where((a) => a.method == 'sessions.stop'), isEmpty);
      await model.selectPeer(mac);
      await model.create();
      expect(client.calls.last.id, isNot('interrupted-request'));
    },
  );
  test(
    'unpaired pending machine cannot be redirected to another machine',
    () async {
      store.value = {
        'peer': 'missing',
        'id': 'old',
        'root_id': 'life',
        'relative_path': '',
      };
      await model.initialize([other]);
      expect(model.error, contains('no longer paired'));
      await model.selectPeer(other);
      expect(client.calls, isEmpty);
      expect(store.value?['id'], 'old');
    },
  );
}
