import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// FIFO of inbound frames with a hard memory bound.
///
/// Dropping a single frame would corrupt the stream, so on overflow the whole
/// backlog is discarded, readers get [overflowError] and [onOverflow] runs
/// (the transport closes; the connection manager reconnects and re-syncs).
class BoundedMsgQueue {
  BoundedMsgQueue({
    required this.overflowError,
    required this.closedError,
    this.onOverflow,
    this.maxFrames = 4000,
    this.maxBytes = 32 * 1024 * 1024,
  });

  final Object overflowError;
  final Object closedError;
  final void Function()? onOverflow;
  final int maxFrames;
  final int maxBytes;

  final _buf = Queue<Uint8List>();
  final _waiters = Queue<Completer<Uint8List>>();
  int _bytes = 0;
  bool _closed = false;
  Object? _failure;

  int get length => _buf.length;
  int get bytes => _bytes;

  void add(Uint8List msg) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(msg);
      return;
    }
    if (_closed) return;
    _buf.addLast(msg);
    _bytes += msg.length;
    if (_buf.length > maxFrames || _bytes > maxBytes) {
      _buf.clear();
      _bytes = 0;
      _closed = true;
      _failure = overflowError;
      onOverflow?.call();
    }
  }

  void error(Object e) {
    for (final w in _waiters) {
      w.completeError(e);
    }
    _waiters.clear();
    _closed = true;
    _failure = e;
  }

  void close() {
    for (final w in _waiters) {
      w.completeError(closedError);
    }
    _waiters.clear();
    _closed = true;
  }

  Future<Uint8List> next() {
    if (_buf.isNotEmpty) {
      final m = _buf.removeFirst();
      _bytes -= m.length;
      return Future.value(m);
    }
    if (_closed) return Future.error(_failure ?? closedError);
    final c = Completer<Uint8List>();
    _waiters.addLast(c);
    return c.future;
  }
}
