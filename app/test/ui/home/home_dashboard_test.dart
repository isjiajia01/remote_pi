import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

const mac = PeerRecord(
  remoteEpk: 'mac',
  sessionName: 'Mac',
  relayUrl: 'ws://x',
  pairedAt: '2026-01-01',
);
const other = PeerRecord(
  remoteEpk: 'other',
  sessionName: 'Other',
  relayUrl: 'ws://x',
  pairedAt: '2026-01-01',
);

HomeItem item(
  String name,
  AgentStatus status, {
  int? at,
  PeerRecord peer = mac,
}) => HomeItem(
  peer: peer,
  room: RoomInfo(roomId: name, name: name, startedAt: 1),
  lastKnownStatus: status,
  activity: SessionIndexRecord(
    epk: peer.remoteEpk,
    roomId: name,
    lastMessageAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
  ),
);

void main() {
  test(
    'status precedence: offline/unannounced, unknown, working, online; never Idle',
    () {
      AgentStatus derive(
        PresenceState presence,
        bool announced,
        bool working,
      ) => deriveAgentStatus(
        presence: presence,
        announced: announced,
        working: working,
      );
      expect(derive(const PresenceOffline(), true, true), AgentStatus.offline);
      expect(derive(const PresenceOnline(), false, true), AgentStatus.offline);
      expect(derive(const PresenceUnknown(), false, true), AgentStatus.offline);
      expect(derive(const PresenceUnknown(), true, true), AgentStatus.checking);
      expect(derive(const PresenceOnline(), true, true), AgentStatus.working);
      expect(derive(const PresenceOnline(), true, false), AgentStatus.online);
      expect(AgentStatus.online.label, 'Online');
    },
  );

  test(
    'sort uses working/online/checking/offline then activity descending then name',
    () {
      final items = [
        item('offline', AgentStatus.offline, at: 100),
        item('checking', AgentStatus.checking, at: 200),
        item('Beta', AgentStatus.online, at: 10),
        item('Alpha', AgentStatus.online, at: 10),
        item('recent', AgentStatus.online, at: 20),
        item('working', AgentStatus.working),
      ]..sort(compareHomeItems);
      expect(items.map((i) => i.displayName), [
        'working',
        'recent',
        'Alpha',
        'Beta',
        'checking',
        'offline',
      ]);
    },
  );

  HomeList list({
    HomeGrouping grouping = HomeGrouping.machine,
    HomeFilter filter = HomeFilter.all,
    HomeRelay relay = HomeRelay.connected,
  }) => HomeList(
    peers: [mac, other],
    grouping: grouping,
    filter: filter,
    relay: relay,
    roomsByPeer: {
      'mac': [const RoomInfo(roomId: 'one', cwd: '/a/project', startedAt: 1)],
      'other': [
        const RoomInfo(roomId: 'two', cwd: '/b/project', startedAt: 1),
        const RoomInfo(roomId: 'three', cwd: '/b/alpha', startedAt: 1),
      ],
    },
    statusesByRoom: {
      'mac:one': AgentStatus.online,
      'other:two': AgentStatus.working,
      'other:three': AgentStatus.offline,
    },
  );

  test('groups are projects: working first, offline-only projects last', () {
    final groups = list().groups();
    expect(groups.map((g) => g.label), ['project', 'alpha']);
    expect(groups.first.sessions.map((s) => s.item.room.roomId), [
      'two',
      'one',
    ]);
    expect(groups.last.isLive, isFalse);
    expect(groups.last.offline.single.room.roomId, 'three');
  });
  test(
    'project grouping combines cwd basenames across machines, working groups first',
    () {
      final groups = list(grouping: HomeGrouping.project).groups();
      expect(groups.map((g) => g.label), ['project', 'alpha']);
      expect(groups.first.items.map((i) => i.peer.remoteEpk), ['other', 'mac']);
    },
  );
  test(
    'stale retains last-known ordering and filter; all rows expose Stale',
    () {
      final state = list(relay: HomeRelay.offline, filter: HomeFilter.working);
      final items = state.visibleItems();
      expect(items, hasLength(1));
      expect(items.single.status, AgentStatus.stale);
      expect(items.single.lastKnownStatus, AgentStatus.working);
      expect(state, isNot(list()));
    },
  );
  test('paired machines without rooms are listed as empty peers', () {
    final state = HomeList(peers: [mac], relay: HomeRelay.connected);
    expect(state.groups(), isEmpty);
    expect(state.emptyPeers().single.remoteEpk, 'mac');
    expect(list().emptyPeers(), isEmpty);
  });
}
