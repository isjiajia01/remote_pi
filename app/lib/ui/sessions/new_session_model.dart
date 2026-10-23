import 'dart:async';
import 'dart:convert';

import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/control_client.dart';
import 'package:app/domain/entities/perch_control.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Written before dispatch so an uncertain creation survives app termination.
class PendingSessionStore {
  const PendingSessionStore();
  static const _key = 'perch.pending_session_create';
  static const _storage = FlutterSecureStorage();
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic>? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(value));
}

class NewSessionModel extends ChangeNotifier {
  NewSessionModel(this.connection, this.client, this.store);
  final ConnectionManager connection;
  final ControlClient client;
  final PendingSessionStore store;
  List<PeerRecord> peers = [];
  PeerRecord? peer;
  List<Map<String, dynamic>> roots = [];
  Map<String, dynamic>? root;
  String path = '';
  List<Map<String, dynamic>> directories = [];
  int? nextOffset;
  Map<String, dynamic>? session;
  Map<String, dynamic>? pending;
  String? error;
  bool busy = false;
  bool ready = false;
  bool _disposed = false;
  int _operation = 0;
  Completer<void>? _cancelWait;
  bool get hasPending => pending != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } on ControlFailure catch (e) {
      error = switch (e.code) {
        'offline' || 'timeout' =>
          'Cannot reach the session service. Check that your Mac is awake, online, and its Perch session service is running. Retry to recover the same request.',
        'unsupported' =>
          'This Mac needs the Perch session service set up before you can create sessions.',
        'forbidden' || 'unauthorized' =>
          'This phone does not have permission to use this folder. Check the Mac’s Perch session permissions.',
        _ => e.message,
      };
    } catch (_) {
      error =
          'Could not complete this operation. Check the connection and retry.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> initialize(List<PeerRecord> machines) => _run(() async {
    peers = machines;
    pending = await store.read();
    if (pending != null) {
      peer = peers.where((p) => p.remoteEpk == pending!['peer']).firstOrNull;
      if (peer == null) {
        error =
            'The machine for the pending request is no longer paired. Pair it again to recover the request.';
        return;
      }
      path = pending!['relative_path'] as String;
      await _recover();
    }
  });

  Future<void> _connect() async {
    final selected = peer!;
    await connection.switchTo(selected);
    if (connection.activePeer?.remoteEpk != selected.remoteEpk ||
        connection.channel == null) {
      throw const ControlFailure('offline', 'Machine unavailable');
    }
    final capabilities = await client.capabilities();
    if (!{
      'directories.roots',
      'directories.list',
      'sessions.create',
      'sessions.get',
      'sessions.stop',
    }.every(capabilities.methods.contains)) {
      throw const ControlFailure('unsupported', 'Session service unavailable');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params, {
    String? id,
  }) async {
    if (connection.activePeer?.remoteEpk != peer?.remoteEpk) {
      throw const ControlFailure('offline', 'Selected machine changed');
    }
    return (await client.execute(
      ControlAction(id ?? 'session_${uuid7()}', method, params, null),
    )).data;
  }

  Future<void> selectPeer(PeerRecord value) => _run(() async {
    if (hasPending) return;
    peer = value;
    roots = [];
    root = null;
    directories = [];
    path = '';
    await _connect();
    roots = List<Map<String, dynamic>>.from(
      (await _request('directories.roots', {}))['roots'] as List,
    );
    if (roots.length == 1) {
      root = roots.single;
      await _list('');
    }
  });

  Future<void> selectRoot(Map<String, dynamic> value) => _run(() async {
    root = value;
    path = '';
    directories = [];
    nextOffset = null;
    await _connect();
    await _list('');
  });

  Future<void> _list(String value, {int offset = 0}) async {
    final data = await _request('directories.list', {
      'root_id': root!['id'],
      'relative_path': value,
      'offset': offset,
    });
    final page = List<Map<String, dynamic>>.from(data['directories'] as List);
    path = value;
    directories = offset == 0 ? page : [...directories, ...page];
    nextOffset = data['next_offset'] as int?;
  }

  Future<void> browse(String value) => _run(() async {
    await _connect();
    await _list(value);
  });

  Future<void> more() => _run(() async {
    await _connect();
    if (nextOffset != null) await _list(path, offset: nextOffset!);
  });

  Future<void> create() => _run(() async {
    if (hasPending) return;
    final request = <String, dynamic>{
      'id': 'create_${uuid7()}',
      'peer': peer!.remoteEpk,
      'root_id': root!['id'],
      'relative_path': path,
    };
    // Do not expose a retryable request until it is durably saved.
    await store.write(request);
    pending = request;
    await _recover();
  });

  Future<void> retry() => _run(() async {
    if (hasPending) {
      peer = peers.where((p) => p.remoteEpk == pending!['peer']).firstOrNull;
      if (peer == null) {
        throw const ControlFailure(
          'offline',
          'Pair the original machine again to recover this request.',
        );
      }
      await _recover();
    } else if (peer != null) {
      await _connect();
      if (root != null) {
        await _list(path);
      } else {
        roots = List<Map<String, dynamic>>.from(
          (await _request('directories.roots', {}))['roots'] as List,
        );
      }
    }
  });

  Future<void> _recover() async {
    await _connect();
    final p = pending!;
    try {
      session = await _request('sessions.create', {
        'root_id': p['root_id'],
        'relative_path': p['relative_path'],
      }, id: p['id'] as String);
    } on ControlFailure catch (e) {
      // The service returns invalid_argument before recording or spawning a
      // creation. Unknown outcomes and permission changes retain the ID.
      if (e.code == 'invalid_argument' && session == null) {
        await _clear();
        root = null;
        path = '';
        directories = [];
        nextOffset = null;
      }
      rethrow;
    }
    await _waitUntilLive();
  }

  Future<void> _waitUntilLive() async {
    final operation = ++_operation;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    final live = Completer<void>();
    final cancelled = Completer<void>();
    _cancelWait = cancelled;
    void checkRoom() {
      if (!live.isCompleted &&
          connection.isRoomLive(
            peer!.remoteEpk,
            session!['room_id'] as String,
          )) {
        live.complete();
      }
    }

    final subscription = connection.roomsStream.listen((_) => checkRoom());
    // Subscribe before checking to include rooms announced during creation.
    checkRoom();
    try {
      while (!_disposed && operation == _operation) {
        final current = session!;
        // A process running is not proof its chat is ready.
        if (live.isCompleted ||
            connection.isRoomLive(
              peer!.remoteEpk,
              current['room_id'] as String,
            )) {
          ready = true;
          return;
        }
        if (['failed', 'stopped', 'interrupted'].contains(current['state'])) {
          error =
              current['error'] as String? ??
              'Session ${current['state']}. You can resolve this request before starting another.';
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          error =
              'Pi started but its chat is not online yet. Retry to check the same session, or stop it.';
          return;
        }
        // Room announcements wake this immediately; process-state polling is
        // only a fallback for startup failures, not the chat readiness signal.
        await Future.any<void>([
          live.future,
          cancelled.future,
          Future<void>.delayed(const Duration(seconds: 3)),
        ]);
        if (_disposed || operation != _operation) return;
        if (live.isCompleted) continue;
        final status = _request('sessions.get', {
          'session_id': current['session_id'],
        });
        final result = await Future.any<Map<String, dynamic>?>([
          status,
          live.future.then((_) => null),
          cancelled.future.then((_) => null),
        ]);
        if (_disposed || operation != _operation) return;
        if (result != null) session = result;
      }
    } finally {
      await subscription.cancel();
      if (identical(_cancelWait, cancelled)) _cancelWait = null;
    }
  }

  Future<void> stop() => _run(() async {
    await _connect();
    // Recover an unknown create result first, using its original ID.
    if (session == null) {
      final p = pending!;
      session = await _request('sessions.create', {
        'root_id': p['root_id'],
        'relative_path': p['relative_path'],
      }, id: p['id'] as String);
    }
    session = await _request('sessions.stop', {
      'session_id': session!['session_id'],
    });
    await _clear();
  });

  Future<void> resolveTerminal() => _run(() async {
    if (session != null && ['failed', 'stopped'].contains(session!['state'])) {
      await _clear();
    }
  });

  /// Only invoked after the user confirms local orphan cleanup. This clears
  /// phone bookkeeping; the backend replay record remains intact.
  Future<void> acknowledgeInterrupted() => _run(() async {
    if (session?['state'] == 'interrupted') await _clear();
  });

  Future<void> completeOpening() async {
    if (!ready) return;
    await store.write(null);
    pending = null;
  }

  Future<void> _clear() async {
    await store.write(null);
    pending = null;
    session = null;
    ready = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    final cancel = _cancelWait;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    client.dispose();
    super.dispose();
  }
}
