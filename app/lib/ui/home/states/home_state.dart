import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:app/ui/home/states/agent_identity.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals;

sealed class HomeState {
  const HomeState();
}

enum HomeFilter { all, working, online, offline }

enum HomeRelay { connected, connecting, offline }

class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeNoPeer extends HomeState {
  const HomeNoPeer();
}

String machineLabel(PeerRecord peer) => (peer.nickname?.isNotEmpty ?? false)
    ? peer.nickname!
    : peer.sessionName.replaceFirst(
        RegExp(r'\.local$', caseSensitive: false),
        '',
      );

String projectLabel(RoomInfo room) =>
    room.cwd?.split('/').where((s) => s.isNotEmpty).lastOrNull ??
    'Unknown project';

/// Presence and room announcement both gate reachability. Missing working
/// metadata on a live agent means Online, never Idle.
AgentStatus deriveAgentStatus({
  required PresenceState presence,
  required bool announced,
  required bool working,
}) {
  if (presence is PresenceOffline || !announced) return AgentStatus.offline;
  if (presence is PresenceUnknown) return AgentStatus.checking;
  return working ? AgentStatus.working : AgentStatus.online;
}

class HomeItem {
  final PeerRecord peer;
  final RoomInfo room;
  final AgentStatus lastKnownStatus;
  final bool stale;
  final SessionIndexRecord? activity;

  /// Last time this phone saw the room working (in memory, this app run).
  final DateTime? workingSeenAt;

  const HomeItem({
    required this.peer,
    required this.room,
    this.lastKnownStatus = AgentStatus.checking,
    this.stale = false,
    this.activity,
    this.workingSeenAt,
  });

  String get key => '${peer.remoteEpk}:${room.roomId}';
  RoomKind get kind => roomKindOf(room.roomId);
  AgentStatus get status => stale ? AgentStatus.stale : lastKnownStatus;
  bool get isLive => lastKnownStatus != AgentStatus.offline;
  String get displayName => sessionTitle(room);

  /// Best local estimate of when the session last did anything: last synced
  /// message, last observed turn, or relay connect time. Never later than
  /// the truth for an unwatched session, so "idle Xh" may overstate.
  DateTime get idleSince {
    var at = DateTime.fromMillisecondsSinceEpoch(room.startedAt);
    for (final t in [activity?.lastMessageAt, workingSeenAt]) {
      if (t != null && t.isAfter(at)) at = t;
    }
    return at;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeItem &&
      other.peer.remoteEpk == peer.remoteEpk &&
      other.room == room &&
      other.lastKnownStatus == lastKnownStatus &&
      other.stale == stale &&
      other.activity == activity &&
      other.workingSeenAt == workingSeenAt;

  @override
  int get hashCode => Object.hash(
    peer.remoteEpk,
    room,
    lastKnownStatus,
    stale,
    activity,
    workingSeenAt,
  );
}

int compareHomeItems(HomeItem a, HomeItem b) {
  int rank(AgentStatus status) => switch (status) {
    AgentStatus.working => 0,
    AgentStatus.online => 1,
    AgentStatus.checking || AgentStatus.unknown => 2,
    AgentStatus.offline || AgentStatus.stale => 3,
  };
  final status = rank(a.lastKnownStatus).compareTo(rank(b.lastKnownStatus));
  if (status != 0) return status;
  final activity = (b.activity?.lastMessageAt?.millisecondsSinceEpoch ?? 0)
      .compareTo(a.activity?.lastMessageAt?.millisecondsSinceEpoch ?? 0);
  if (activity != 0) return activity;
  final name = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  return name != 0 ? name : a.key.compareTo(b.key);
}

/// A main session with the sub-agent runs it launched (never peers).
class HomeSession {
  const HomeSession(this.item, [this.subagents = const []]);
  final HomeItem item;
  final List<HomeItem> subagents;
  bool get hasWorking =>
      item.lastKnownStatus == AgentStatus.working ||
      subagents.any((s) => s.lastKnownStatus == AgentStatus.working);
}

/// One project (cwd folder name, across machines).
class HomeGroup {
  const HomeGroup({
    required this.key,
    required this.label,
    this.path,
    this.sessions = const [],
    this.offline = const [],
    this.orphans = const [],
    this.peer,
  });
  final String key;
  final String label;
  final String? path;

  /// Live main sessions (working, idle, checking), each with its sub-agents.
  final List<HomeSession> sessions;

  /// Main sessions that are no longer announced (cached by this phone).
  final List<HomeItem> offline;

  /// Live sub-agents whose parent is not listed (old parent extension, or
  /// the parent went offline first).
  final List<HomeItem> orphans;
  final PeerRecord? peer;

  List<HomeItem> get items => [for (final s in sessions) s.item, ...offline];
  bool get isLive => sessions.isNotEmpty || orphans.isNotEmpty;
  bool get hasWorking =>
      sessions.any((s) => s.hasWorking) ||
      orphans.any((s) => s.lastKnownStatus == AgentStatus.working);
}

class HomeList extends HomeState {
  final List<PeerRecord> peers;
  final Map<String, PresenceState> statusByEpk;
  final Map<String, List<RoomInfo>> roomsByPeer;

  /// Keys use the storage EPK spelling, like HomeItem.key. These are retained
  /// through relay loss rather than replacing last-known status with Offline.
  final Map<String, AgentStatus> statusesByRoom;
  final Map<String, SessionIndexRecord> activityByRoom;
  final Map<String, DateTime> workingSeenByRoom;
  final HomeFilter filter;

  /// Retained for preference compatibility; Home always groups by project.
  final HomeGrouping grouping;
  final HomeRelay relay;
  final DateTime? staleSince;
  final DateTime? now;

  const HomeList({
    required this.peers,
    this.statusByEpk = const {},
    this.roomsByPeer = const {},
    this.statusesByRoom = const {},
    this.activityByRoom = const {},
    this.workingSeenByRoom = const {},
    this.filter = HomeFilter.all,
    this.grouping = HomeGrouping.machine,
    this.relay = HomeRelay.connecting,
    this.staleSince,
    this.now,
  });

  HomeList copyWith({
    List<PeerRecord>? peers,
    Map<String, PresenceState>? statusByEpk,
    Map<String, List<RoomInfo>>? roomsByPeer,
    Map<String, AgentStatus>? statusesByRoom,
    Map<String, SessionIndexRecord>? activityByRoom,
    Map<String, DateTime>? workingSeenByRoom,
    HomeFilter? filter,
    HomeGrouping? grouping,
    HomeRelay? relay,
    DateTime? staleSince,
    DateTime? now,
  }) => HomeList(
    peers: peers ?? this.peers,
    statusByEpk: statusByEpk ?? this.statusByEpk,
    roomsByPeer: roomsByPeer ?? this.roomsByPeer,
    statusesByRoom: statusesByRoom ?? this.statusesByRoom,
    activityByRoom: activityByRoom ?? this.activityByRoom,
    workingSeenByRoom: workingSeenByRoom ?? this.workingSeenByRoom,
    filter: filter ?? this.filter,
    grouping: grouping ?? this.grouping,
    relay: relay ?? this.relay,
    staleSince: staleSince ?? this.staleSince,
    now: now ?? this.now,
  );

  /// Every announced or cached room, sub-agent runs included.
  List<HomeItem> allItems({String Function(String)? normalizeEpk}) {
    final out = <HomeItem>[];
    for (final peer in peers) {
      final epk = normalizeEpk?.call(peer.remoteEpk) ?? peer.remoteEpk;
      for (final room in roomsByPeer[epk] ?? <RoomInfo>[]) {
        final key = '${peer.remoteEpk}:${room.roomId}';
        out.add(
          HomeItem(
            peer: peer,
            room: room,
            lastKnownStatus: statusesByRoom[key] ?? AgentStatus.checking,
            stale: relay != HomeRelay.connected,
            activity: activityByRoom['$epk:${room.roomId}'],
            workingSeenAt: workingSeenByRoom[key],
          ),
        );
      }
    }
    out.sort(compareHomeItems);
    return out;
  }

  /// Main sessions only: sub-agent runs are details of their parent and are
  /// never counted or filtered as agents of their own.
  List<HomeItem> items({String Function(String)? normalizeEpk}) => allItems(
    normalizeEpk: normalizeEpk,
  ).where((i) => !i.kind.isSubagent).toList();

  bool _matches(AgentStatus status) => switch (filter) {
    HomeFilter.all => true,
    HomeFilter.working => status == AgentStatus.working,
    HomeFilter.online => status == AgentStatus.online,
    HomeFilter.offline => status == AgentStatus.offline,
  };

  List<HomeItem> visibleItems({String Function(String)? normalizeEpk}) => items(
    normalizeEpk: normalizeEpk,
  ).where((i) => _matches(i.lastKnownStatus)).toList();

  /// Project cards: live sessions with nested sub-agents, then offline rows.
  /// Offline sub-agent runs are finished work and are dropped. Sort: any
  /// working first, then any live, then name.
  List<HomeGroup> groups({String Function(String)? normalizeEpk}) {
    final all = allItems(normalizeEpk: normalizeEpk);
    final mains = all.where((i) => !i.kind.isSubagent).toList();
    final subs = all.where((i) => i.kind.isSubagent && i.isLive).toList();
    final childrenOf = <String, List<HomeItem>>{};
    final liveMainKeys = {
      for (final m in mains)
        if (m.isLive) m.key,
    };
    final orphans = <HomeItem>[];
    for (final sub in subs) {
      final parent = sub.kind.parentRoomId;
      final key = parent == null ? null : '${sub.peer.remoteEpk}:$parent';
      if (key != null && liveMainKeys.contains(key)) {
        (childrenOf[key] ??= []).add(sub);
      } else {
        orphans.add(sub);
      }
    }
    final sessions = <String, List<HomeSession>>{};
    final offline = <String, List<HomeItem>>{};
    final orphanBy = <String, List<HomeItem>>{};
    final paths = <String, String>{};
    for (final m in mains) {
      final session = HomeSession(m, childrenOf[m.key] ?? const []);
      final visible = m.isLive
          ? _matches(m.lastKnownStatus) ||
                filter == HomeFilter.working && session.hasWorking
          : _matches(AgentStatus.offline);
      if (!visible) continue;
      final key = projectLabel(m.room);
      if (m.room.cwd != null) paths.putIfAbsent(key, () => m.room.cwd!);
      if (m.isLive) {
        (sessions[key] ??= []).add(session);
      } else {
        (offline[key] ??= []).add(m);
      }
    }
    for (final o in orphans) {
      if (!(filter == HomeFilter.all ||
          filter == HomeFilter.working &&
              o.lastKnownStatus == AgentStatus.working)) {
        continue;
      }
      final key = projectLabel(o.room);
      if (o.room.cwd != null) paths.putIfAbsent(key, () => o.room.cwd!);
      (orphanBy[key] ??= []).add(o);
    }
    final keys = {...sessions.keys, ...offline.keys, ...orphanBy.keys};
    final groups = [
      for (final key in keys)
        HomeGroup(
          key: key,
          label: key,
          path: paths[key],
          sessions: sessions[key] ?? const [],
          offline: offline[key] ?? const [],
          orphans: orphanBy[key] ?? const [],
        ),
    ];
    groups.sort((a, b) {
      if (a.hasWorking != b.hasWorking) return a.hasWorking ? -1 : 1;
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return groups;
  }

  /// Paired machines with no rooms at all (live or cached).
  List<PeerRecord> emptyPeers({String Function(String)? normalizeEpk}) => [
    for (final peer in peers)
      if ((roomsByPeer[normalizeEpk?.call(peer.remoteEpk) ?? peer.remoteEpk] ??
              const <RoomInfo>[])
          .isEmpty)
        peer,
  ];

  @override
  bool operator ==(Object other) =>
      other is HomeList &&
      other.filter == filter &&
      other.grouping == grouping &&
      other.relay == relay &&
      other.staleSince == staleSince &&
      other.now == now &&
      listEquals(other.peers, peers) &&
      mapEquals(other.statusByEpk, statusByEpk) &&
      mapEquals(other.roomsByPeer, roomsByPeer) &&
      mapEquals(other.statusesByRoom, statusesByRoom) &&
      mapEquals(other.activityByRoom, activityByRoom) &&
      mapEquals(other.workingSeenByRoom, workingSeenByRoom);

  @override
  int get hashCode => Object.hash(
    filter,
    grouping,
    relay,
    staleSince,
    now,
    Object.hashAll(peers),
    Object.hashAllUnordered(
      statusesByRoom.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      activityByRoom.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      workingSeenByRoom.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
