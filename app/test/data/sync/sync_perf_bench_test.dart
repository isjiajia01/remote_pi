// Perf regression bench for streaming path. Prints metrics; asserts bounds.
import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _Ch implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _control = StreamController<ControlInbound>.broadcast();
  final sent = <ClientMessage>[];
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Stream<ControlInbound> get controlFrames => _control.stream;
  @override
  Future<void> send(ClientMessage msg) async => sent.add(msg);
  @override
  void sendControl(Map<String, dynamic> json) {}
  @override
  Future<void> close() async {
    await _ctrl.close();
    await _control.close();
  }

  void push(ServerMessage m) => _ctrl.add(m);
}

class _Store extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('rp_perf_');
    await LocalBoxes.initForTest(dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('BENCH 200 chunks @5ms: index writes and UI flush cadence', () async {
    final ch = _Ch();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: _Store(),
      emitDebounce: Duration.zero,
    );
    final sync = SyncService(conn, LocalBoxes());
    conn.adopt(
      ch,
      const PeerRecord(
        remoteEpk: 'epk_bench',
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final idx = LocalBoxes().sessionsIndexBox();
    var puts = 0;
    final sub = idx.watch().listen((_) => puts++);
    final flushAt = <int>[];
    final sw = Stopwatch()..start();
    final sub2 = sync.streamingStream.listen((m) {
      if (m != null) flushAt.add(sw.elapsedMilliseconds);
    });
    const n = 200;
    for (var i = 0; i < n; i++) {
      ch.push(AgentChunk(inReplyTo: 'turn1', delta: 'tok$i '));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final streamEnd = sw.elapsedMilliseconds;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final putsDuring = puts;
    var maxGap = 0;
    for (var i = 1; i < flushAt.length; i++) {
      final g = flushAt[i] - flushAt[i - 1];
      if (g > maxGap) maxGap = g;
    }
    final firstFlush = flushAt.isEmpty ? -1 : flushAt.first;
    // ignore: avoid_print
    print(
      'BENCH chunks=$n streamMs=$streamEnd indexPuts=$putsDuring '
      'uiFlushes=${flushAt.length} firstFlushMs=$firstFlush maxGapMs=$maxGap',
    );
    // Loose bounds (baseline: puts=200, flushes=5, maxGap>500ms).
    expect(putsDuring, lessThanOrEqualTo(3));
    expect(flushAt.length, greaterThanOrEqualTo(30));
    expect(maxGap, lessThan(250));
    await sub.cancel();
    await sub2.cancel();
    sync.dispose();
    conn.dispose();
  });

  test('BENCH duplicate session_sync requests', () async {
    final ch = _Ch();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: _Store(),
      emitDebounce: Duration.zero,
    );
    final sync = SyncService(conn, LocalBoxes());
    conn.adopt(
      ch,
      const PeerRecord(
        remoteEpk: 'epk_bench2',
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // ChatViewModel bootstrap + online-edge + manual retry, back to back.
    sync.requestSync();
    sync.requestSync();
    sync.requestSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final n = ch.sent.whereType<SessionSync>().length;
    // ignore: avoid_print
    print('BENCH syncRequests=$n (3 manual + online-edge debounce)');
    expect(n, 1);
    // After the reply arrives a new request must go out again.
    final id = ch.sent.whereType<SessionSync>().first.id;
    ch.push(
      SessionHistory(
        inReplyTo: id,
        sessionStartedAt: 1,
        events: const [],
        eos: true,
        truncated: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sync.requestSync();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final after = ch.sent.whereType<SessionSync>().length;
    // ignore: avoid_print
    print('BENCH syncRequestsAfterReply=$after');
    expect(after, greaterThan(n));
    sync.dispose();
    conn.dispose();
  });
}
