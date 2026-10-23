# Streaming performance pass 1 (2026-10-23)

Source of priorities: Oracle source review (hypotheses until measured). Benchmarks: `app/test/data/sync/sync_perf_bench_test.dart`, `pi-extension/src/sync_perf.test.ts` (Flutter test VM / Node on a dev Mac; not on-device, not a frame-time measurement).

| Metric (200 chunks @5ms, Flutter VM) | Before | After |
|---|---|---|
| Durable index writes | 200 | 1 |
| UI flushes during ~1.7s stream | 5 | 80 |
| First flush | 61-681 ms | 28 ms |
| Longest gap between flushes | 558-851 ms | 41 ms |
| `session_sync` requests (3 manual + online edge) | 4 | 1 (a new one is sent after the reply) |

Changes (`app/lib/data/sync/sync_service.dart`):
1. `_setActivity` skips the Hive put when status is unchanged and there is no preview; memo reset on index wipe.
2. Chunk flush is a fixed 16 ms window (arm once, append meanwhile) instead of cancel/re-arm debounce. Boundaries (tool, done, error) still drain it.
3. `requestSync` is single-flight; cleared by history reply, channel change, session switch, dispose, or 5 s timeout.

Not changed, by measurement: extension `session_sync` mapping costs 0.53 ms per call at 10 500 messages (50 calls = 26.5 ms), so no incremental cache was added.
Extension test `sync_perf.test.ts` guards correctness: tail output equals a fresh full mapping, including after appends.

Verification: flutter analyze clean; extension typecheck + 890 tests passed. App serial full run: 682 passed, 1 skipped, 1 failed — the pre-existing timing-sensitive `sync_service_test` group. Control: that file failed 2/12 runs on the original code and 1/12 with these changes, so it is flaky independent of this work (not fixed).

Unmeasured: real-device frame timing, energy, relay/network effects, Markdown rebuild cost. Extension chunk coalescing and client queue limits are covered in pass 2 below. Relay queue limits, long-chat rebuild and lifecycle work remain undone.

## Pass 2: extension chunk coalescing and bounded queues

| Item | Before | After | Where |
|---|---|---|---|
| Extension wire frames for 200 text deltas arriving 1 ms apart | 200 | 14 | `pi-extension/src/transport/chunk_coalescer.ts`, wired in `index.ts` (`_chunks`) |
| Delta text integrity / order | n/a | identical concatenation; any non-chunk frame flushes first; turn change flushes | `chunk_coalescer.test.ts` |
| Extension relay socket backlog | unbounded | socket reset at 16 MiB unsent (`PERCH_WS_MAX_BUFFER`); reconnect + `session_sync` recover | `relay_client.ts` |
| App inbound queue | unbounded `List`, `removeAt(0)` | `BoundedMsgQueue`: 4000 frames / 32 MiB, then drop backlog, close socket, reconnect | `app/lib/data/transport/bounded_msg_queue.dart` |
| App queue drain, 20 000 frames (Dart VM) | 739 ms | 93 ms | `bounded_msg_queue_test.dart`, `/tmp/perch-tools/oldq.dart` |

Design notes: first delta after idle is sent immediately (no added latency), later deltas share a 16 ms fixed window (`PERCH_CHUNK_WINDOW_MS`), 8 KiB cap. Overflow policy is reset-and-resync, never silent frame drops, since a missing delta would corrupt the stream.

Not done: the relay's per-connection `mpsc::unbounded_channel` (`relay/src/handlers/peer.rs:138`, `peers/registry.rs`). The relay source and deployed service were left unchanged; the client's caps do not bound the relay's own queues. Suggested design: per-connection pending-byte counter, close the connection above a cap, same resync path. The two client-side caps above bound each end meanwhile.

Device follow-up: the final app and extension ran a 150-line response on a physical iPhone; incremental text and the final marker were observed, and the composer returned to idle. Accessibility-tree A/B sampling proved unreliable and yields no valid frame-time or speedup result. Home activity time/preview remained stale in both the old and optimized SyncService builds; this issue is unresolved.

Verification: extension typecheck; 895 tests pass with `PERCH_FULL_FEATURES=1` (8 existing full-mode tests fail without it, in files not touched here); App serial full run 688 passed, 1 skipped, `flutter analyze` clean. Not measured: real-device frame time, end-to-end latency with a real provider, actual coalescing ratio on real token timing.
