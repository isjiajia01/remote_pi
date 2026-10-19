import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
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

String machineLabel(PeerRecord peer) =>
    (peer.nickname?.isNotEmpty ?? false) ? peer.nickname! : peer.sessionName;

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

  const HomeItem({
    required this.peer,
    required this.room,
    this.lastKnownStatus = AgentStatus.checking,
    this.stale = false,
    this.activity,
  });

  String get key => '${peer.remoteEpk}:${room.roomId}';
  AgentStatus get status => stale ? AgentStatus.stale : lastKnownStatus;
  String get displayName {
    if (room.name?.isNotEmpty ?? false) return room.name!;
    if (room.cwd?.isNotEmpty ?? false) return projectLabel(room);
    return machineLabel(peer);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeItem &&
      other.peer.remoteEpk == peer.remoteEpk &&
      other.room == room &&
      other.lastKnownStatus == lastKnownStatus &&
      other.stale == stale &&
      other.activity == activity;

  @override
  int get hashCode =>
      Object.hash(peer.remoteEpk, room, lastKnownStatus, stale, activity);
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

class HomeGroup {
  const HomeGroup({
    required this.key,
    required this.label,
    required this.items,
    this.peer,
  });
  final String key;
  final String label;
  final List<HomeItem> items;
  final PeerRecord? peer;
  bool get hasWorking =>
      items.any((i) => i.lastKnownStatus == AgentStatus.working);
}

class HomeList extends HomeState {
  final List<PeerRecord> peers;
  final Map<String, PresenceState> statusByEpk;
  final Map<String, List<RoomInfo>> roomsByPeer;

  /// Keys use the storage EPK spelling, like HomeItem.key. These are retained
  /// through relay loss rather than replacing last-known status with Offline.
  final Map<String, AgentStatus> statusesByRoom;
  final Map<String, SessionIndexRecord> activityByRoom;
  final HomeFilter filter;
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
    filter: filter ?? this.filter,
    grouping: grouping ?? this.grouping,
    relay: relay ?? this.relay,
    staleSince: staleSince ?? this.staleSince,
    now: now ?? this.now,
  );

  List<HomeItem> items({String Function(String)? normalizeEpk}) {
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
          ),
        );
      }
    }
    out.sort(compareHomeItems);
    return out;
  }

  List<HomeItem> visibleItems({String Function(String)? normalizeEpk}) =>
      items(normalizeEpk: normalizeEpk)
          .where(
            (i) => switch (filter) {
              HomeFilter.all => true,
              HomeFilter.working => i.lastKnownStatus == AgentStatus.working,
              HomeFilter.online => i.lastKnownStatus == AgentStatus.online,
              HomeFilter.offline => i.lastKnownStatus == AgentStatus.offline,
            },
          )
          .toList();

  List<HomeGroup> groups({String Function(String)? normalizeEpk}) {
    final itemsByGroup = <String, List<HomeItem>>{};
    final labels = <String, String>{};
    final peersByGroup = <String, PeerRecord>{};
    if (grouping == HomeGrouping.machine && filter == HomeFilter.all) {
      for (final peer in peers) {
        itemsByGroup[peer.remoteEpk] = [];
        labels[peer.remoteEpk] = machineLabel(peer);
        peersByGroup[peer.remoteEpk] = peer;
      }
    }
    for (final item in visibleItems(normalizeEpk: normalizeEpk)) {
      final key = grouping == HomeGrouping.machine
          ? item.peer.remoteEpk
          : projectLabel(item.room);
      (itemsByGroup[key] ??= []).add(item);
      labels[key] = grouping == HomeGrouping.machine
          ? machineLabel(item.peer)
          : key;
      if (grouping == HomeGrouping.machine) peersByGroup[key] = item.peer;
    }
    final groups = [
      for (final entry in itemsByGroup.entries)
        HomeGroup(
          key: entry.key,
          label: labels[entry.key]!,
          items: entry.value,
          peer: peersByGroup[entry.key],
        ),
    ];
    groups.sort((a, b) {
      if (a.hasWorking != b.hasWorking) return a.hasWorking ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return groups;
  }

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
      mapEquals(other.activityByRoom, activityByRoom);

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
  );
}
