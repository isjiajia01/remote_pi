import 'dart:async';

import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/home_read_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/core/widgets/status_dot.dart';
import 'package:app/ui/home/states/home_state.dart';

class HomeViewModel extends ViewModel<HomeState> {
  final PairingStorage _storage;
  final Preferences _prefs;
  final ConnectionManager _conn;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<List<SessionIndexRecord>>? _activitySub;
  Timer? _clock;
  bool _disposed = false;
  Map<String, SessionIndexRecord> _activity = {};
  final _lastKnownStatuses = <String, AgentStatus>{};

  HomeViewModel(
    this._storage,
    this._prefs,
    this._conn, [
    HomeReadRepository? repository,
  ]) : super(const HomeLoading()) {
    _load();
    _presenceSub = _conn.presenceStream.listen((_) => _update());
    _roomsSub = _conn.roomsStream.listen((_) => _update());
    _statusSub = _conn.statusStream.listen((_) => _update());
    _activitySub = repository?.watchSessions().listen((rows) {
      _activity = {
        for (final row in rows)
          '${normalizeEpkForLookup(row.epk)}:${row.roomId}': row,
      };
      final s = state;
      if (s is HomeList) {
        emit(s.copyWith(activityByRoom: _activity));
      }
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      final s = state;
      if (s is HomeList) emit(s.copyWith(now: DateTime.now()));
    });
    _storage.addListener(_onStorageChanged);
  }

  void _onStorageChanged() {
    if (!_disposed) _load();
  }

  bool get isRelayConnected => _conn.status is StatusOnline;
  HomeRelay get relay => switch (_conn.status) {
    StatusOnline() => HomeRelay.connected,
    StatusConnecting() || StatusNoPeer() => HomeRelay.connecting,
    _ => HomeRelay.offline,
  };

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(const HomeNoPeer());
      return;
    }
    _conn.subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
    final previous = state;
    final next = previous is HomeList
        ? previous.copyWith(peers: peers)
        : HomeList(peers: peers, grouping: _prefs.homeGrouping);
    _update(next);
  }

  void _update([HomeList? initial]) {
    final s = initial ?? state;
    if (s is! HomeList || _disposed) return;
    final rooms = _conn.roomsSnapshot;
    if (isRelayConnected) {
      for (final peer in s.peers) {
        for (final room
            in rooms[normalizeEpkForLookup(peer.remoteEpk)] ?? <RoomInfo>[]) {
          _lastKnownStatuses['${peer.remoteEpk}:${room.roomId}'] =
              deriveAgentStatus(
                presence: _conn.presenceFor(peer.remoteEpk),
                announced: _conn.isRoomLive(peer.remoteEpk, room.roomId),
                working: room.working,
              );
        }
      }
    }
    emit(
      s.copyWith(
        activityByRoom: _activity,
        statusByEpk: _conn.presenceSnapshot,
        roomsByPeer: rooms,
        statusesByRoom: Map.of(_lastKnownStatuses),
        relay: relay,
        staleSince:
            s.relay == HomeRelay.connected && !isRelayConnected ||
                s.staleSince == null
            ? DateTime.now()
            : s.staleSince,
      ),
    );
  }

  void setFilter(HomeFilter filter) {
    final s = state;
    if (s is HomeList) emit(s.copyWith(filter: filter));
  }

  Future<void> setGrouping(HomeGrouping grouping) async {
    final s = state;
    if (s is HomeList) emit(s.copyWith(grouping: grouping));
    await _prefs.setHomeGrouping(grouping);
  }

  Future<void> refresh() async {
    final s = state;
    if (s is HomeList) {
      // subscribeToPeers also requests rooms_check and presence_check.
      _conn.subscribeToPeers(s.peers.map((p) => p.remoteEpk).toList());
    }
  }

  Future<void> retry() async {
    final s = state;
    if (s is! HomeList || s.peers.isEmpty) return;
    await _conn.switchTo(_conn.activePeer ?? s.peers.first);
    await refresh();
  }

  List<HomeItem> get visibleItems {
    final s = state;
    return s is HomeList
        ? s.visibleItems(normalizeEpk: normalizeEpkForLookup)
        : [];
  }

  ({int all, int working, int online, int offline}) get counts {
    final s = state;
    final all = s is HomeList
        ? s.items(normalizeEpk: normalizeEpkForLookup)
        : <HomeItem>[];
    int count(AgentStatus status) =>
        all.where((i) => i.lastKnownStatus == status).length;
    return (
      all: all.length,
      working: count(AgentStatus.working),
      online: count(AgentStatus.online),
      offline: count(AgentStatus.offline),
    );
  }

  bool isRoomWorking(String epk, String roomId) =>
      _conn.isRoomWorking(epk, roomId);

  /// Remember which (peer, room) the user picked. Falls back to
  /// `roomId='main'` when the caller doesn't supply one (legacy /
  /// pre-room-announce). Also flips the ConnectionManager's active
  /// room so subsequent sends carry the right outer envelope.
  ///
  /// Plan-24 follow-up: when the peer record in storage has no
  /// `roomId` yet (post-mesh-restore: the mesh blob doesn't carry
  /// per-device room data, so `PeerRecord.roomId` is null until the
  /// relay announces the room and `ConnectionManager._maybeAdoptLegacyRoom`
  /// catches up), persist the tapped roomId on the PeerRecord too.
  /// Without this, the next cold-start reads `peer.roomId=null` →
  /// `ConnectionManager._connect` falls back to room `'main'` → Pi
  /// never sees the frame → ChatViewModel sits on Connecting/offline
  /// even though the WS is alive.
  Future<void> openSession(String epk, {String? roomId}) async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    final match = peers.where((p) => p.remoteEpk == epk).cast<PeerRecord?>();
    if (match.isEmpty) return;
    final peer = match.first!;
    final effectiveRoom = (roomId == null || roomId.isEmpty) ? 'main' : roomId;
    await _prefs.setSelectedRoom(epk: epk, roomId: effectiveRoom);
    if (peer.roomId != effectiveRoom) {
      // ignore: unawaited_futures
      _storage.savePeer(peer.copyWith(roomId: effectiveRoom));
    }
    // Tell the manager which Pi-side room to address. Safe to call
    // even if the manager is mid-connect (room is applied on the next
    // send and any active StatusOnline channel).
    _conn.switchRoom(effectiveRoom);
  }

  /// Helper for widgets: pass a peer's url-safe epk → returns standard
  /// for indexing into [HomeList.roomsByPeer] / [HomeList.statusByEpk].
  static String normalizeEpkForLookup(String epk) => toStandardB64(epk);

  /// Plan-17 follow-up — `true` if `(epk, roomId)` is currently live on
  /// the relay. Drives the presence dot on each tile (per-room, not
  /// per-peer anymore).
  bool isRoomLive(String epk, String roomId) => _conn.isRoomLive(epk, roomId);

  /// Long-press menu — rename a single room locally (Pi never sees it).
  Future<void> renameRoom(String epk, String roomId, String? name) =>
      _conn.setRoomLocalName(epk, roomId, name);

  /// Long-press menu — delete a cached room locally. Caller should
  /// gate on `!isRoomLive` (only offline rooms can be removed).
  Future<void> deleteRoom(String epk, String roomId) =>
      _conn.deleteCachedRoom(epk, roomId);

  @override
  void dispose() {
    _disposed = true;
    _presenceSub?.cancel();
    _roomsSub?.cancel();
    _statusSub?.cancel();
    _activitySub?.cancel();
    _clock?.cancel();
    _storage.removeListener(_onStorageChanged);
    super.dispose();
  }
}
