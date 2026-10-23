import 'dart:typed_data';

import 'package:app/data/transport/bounded_msg_queue.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(int n) => Uint8List(n);

void main() {
  BoundedMsgQueue make({int frames = 4, int bytes = 100, void Function()? o}) =>
      BoundedMsgQueue(
        overflowError: 'overflow',
        closedError: 'closed',
        maxFrames: frames,
        maxBytes: bytes,
        onOverflow: o,
      );

  test('FIFO order, waiter handoff and byte accounting', () async {
    final q = make();
    final w = q.next();
    q.add(_b(1));
    expect((await w).length, 1);
    q.add(_b(2));
    q.add(_b(3));
    expect(q.bytes, 5);
    expect((await q.next()).length, 2);
    expect((await q.next()).length, 3);
    expect(q.bytes, 0);
  });

  test(
    'frame-count overflow discards backlog, fires callback, errors reader',
    () async {
      var fired = 0;
      final q = make(frames: 3, o: () => fired++);
      for (var i = 0; i < 4; i++) {
        q.add(_b(1));
      }
      expect(fired, 1);
      expect(q.length, 0);
      await expectLater(q.next(), throwsA('overflow'));
      q.add(_b(1)); // ignored after failure
      expect(q.length, 0);
    },
  );

  test('byte overflow also trips; drained queue never trips', () async {
    var fired = 0;
    final q = make(frames: 1000, bytes: 50, o: () => fired++);
    for (var i = 0; i < 100; i++) {
      q.add(_b(40));
      await q.next();
    }
    expect(fired, 0);
    q.add(_b(40));
    q.add(_b(40));
    expect(fired, 1);
  });

  test('close completes waiters with closed error', () async {
    final q = make();
    final w = q.next();
    q.close();
    await expectLater(w, throwsA('closed'));
  });

  test('BENCH 20000 frames pop cost', () async {
    final q = make(frames: 30000, bytes: 1 << 30);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20000; i++) {
      q.add(_b(8));
    }
    for (var i = 0; i < 20000; i++) {
      await q.next();
    }
    // ignore: avoid_print
    print('BENCH queue 20000 frames drain ms=${sw.elapsedMilliseconds}');
  });
}
