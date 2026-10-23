import 'dart:async';
import 'package:app/data/transport/channel.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import '../approvals/approval_service_test.dart' as base;

class PushChannel extends base.Channel implements IControlLink {
  final controls = StreamController<ControlInbound>.broadcast();
  final requests = <Map<String, dynamic>>[];
  List<RoomInfo>? snapshot;
  String? snapshotPeer;
  @override
  Stream<ControlInbound> get controlFrames => controls.stream;
  @override
  void sendControl(Map<String, dynamic> json) {
    requests.add(json);
    if (json['type'] == 'rooms_check' && snapshot != null) {
      controls.add(RoomsSnapshot(peer: snapshotPeer!, rooms: snapshot!));
    }
  }
}

class PushStorage extends base.Storage {
  List<PeerRecord> peers = [];
  @override
  Future<List<PeerRecord>> listPeers() async => peers;
  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}
  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => [];
  @override
  Future<void> savePeer(PeerRecord peer) async {}
}
