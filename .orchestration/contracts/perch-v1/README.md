# Perch v1 wire contract

All messages use the existing authenticated relay channel and paired Owner identity. Read/control endpoints emit only responses. Locally enabled tool approvals additionally emit challenges. Capability absence/unsupported leaves legacy clients unchanged.

- `perch_capabilities_get {type,id}` → `perch_capabilities_result {type,id,version:1,methods:["agents.list","agents.events"],scope:"local_broker",ack_semantics:"delivery_only",limits:{retention:512,max_events:128,max_wait_ms:25000,max_subscribers:8}}`.
- `perch_request {type,id,version:1,method,params}` → `perch_result {type,id,version:1,method,result}` or `perch_error {type,id,version:1,error:{code,message}}`. Response `id` echoes request `id`. Supported codes: unauthorized, forbidden, unsupported, invalid_argument, offline, timeout, internal.
- `agents.list` params `{}` → `{scope:"local_broker",epoch,revision,cursor,agents:[{cwd,name,address}]}`. Inventory contains only connected peers on this broker, excluding sibling inventories, relay rooms and installed but disconnected agents. Revision increments for local inventory changes. Snapshot and cursor are captured together.
- `agents.events` params `{epoch?,cursor?,limit?,wait_ms?}` → `{scope:"local_broker",epoch,cursor,events,resync_required}`. Epoch/cursor must occur together; limit defaults to 128 (1–128), wait_ms defaults to zero (0–25000). At most eight pending long polls across all Owners/connections per broker; overflow returns forbidden. An idle long poll returns an empty successful result after wait_ms. Transport failure/timeout is an error, never proof of idle state; clients retain cached data as stale until a successful snapshot/replay.
- Each event has `{cursor,ts,type}` plus either `agent:{cwd,name,address}` for peer_joined/peer_left, or `{id,re,from,to,delivered,ack_status,via}` for routed. No message bodies, prompts or tool arguments. The routing audit covers local UDS routing and inbound relay delivery observed at this broker; outbound cross-PC handoff is outside this broker's delivery audit. ACK received means transport delivery only; it never means task completion.
- Event storage retains the newest 512 records in memory even without an audit file. Epoch is stable for the broker lifetime and changes on restart/failover. Missing, foreign, expired or future cursors return `resync_required:true`, no events and the current cursor. Client must obtain agents.list and resume using that snapshot's epoch/cursor. Retention is a record count, not a time promise.
- Replay is deterministic within retention: the same epoch/cursor yields the same event cursors and original message id/re. Clients reconcile by `(epoch,event.cursor)`; separate deliveries with the same message id can still be distinct audit events. Advance only to the returned cursor, including when a page is full. Inventory events ensure a snapshot can be reconciled with later joins/leaves.

`capabilities.json`, `agents-list.json`, `agents-events.json`, `replay-gap.json` pair requests with exact responses; `errors.json` enumerates error envelopes. Tests consume all fixtures. The local broker endpoint continues to accept only its two read methods. Arbitrary commands and caller-supplied filesystem paths are never accepted.

## Supervisor control endpoint (Phase 4a)

`pi-supervisord` optionally maintains a separate authenticated relay connection in reserved room `perch-control`, named `Perch Control`. It stays alive when every agent is stopped. Existing agent-room capabilities remain unchanged. This is disabled unless the operator creates `~/.pi/remote/perch-control.json` locally before supervisor startup:

```json
{
  "enabled": true,
  "owners": {
    "<canonical standard-base64 Ed25519 Owner public key>": {
      "operations": ["daemon.list", "daemon.start", "daemon.stop", "daemon.restart", "cron.list", "cron.add", "cron.set_enabled", "cron.remove", "cron.run", "cron.log"],
      "daemon_ids": ["1234abcd"]
    }
  }
}
```

The Owner must also remain paired in existing `peers.json`. A grant alone never establishes pairing. Missing, malformed, disabled, unknown-field or invalid-operation/ID configuration denies access. Remote methods cannot modify this file or pairing. Use restrictive local file permissions. The component accepts explicit config/journal/socket paths for isolated tests; the supervisor uses its existing `REMOTE_PI_HOME` override for control files and IPC. Existing identity/pairing storage retains its existing home resolution.

Negotiate `perch_capabilities_get` in the reserved room on every connection/reconnect. Response uses `scope:"supervisor"`, lists only locally granted operations, and reports `limits:{max_prompt_chars:8192,max_log_entries:100}`. The authenticated relay envelope's sender key supplies identity; inner Owner claims are ignored. Every operation rechecks pairing and local grants before effects. Lists are filtered by granted daemon IDs; cron job IDs are resolved against supervisor state to check their target daemon. Stored outcomes require current grants too.

`perch_request {type,id,version:1,method,params,expected_revision?}` returns `perch_result {type,id,version:1,method,result:{scope:"supervisor",revision,data}}` or the common `perch_error`. `data` follows local supervisor IPC responses. Only these exact params are accepted:

| Method | Params | IPC operation |
| --- | --- | --- |
| daemon.list | `{}` | list |
| daemon.start / stop / restart | `{id}` | start / stop / restart |
| cron.list | `{}` | cron_list |
| cron.add | `{daemon_id,schedule,prompt,tz?,skip_if_busy?,wake?,catchup?}` | cron_add |
| cron.set_enabled | `{job_id,enabled}` | cron_enable |
| cron.remove / run | `{job_id}` | cron_remove / cron_run |
| cron.log | `{job_id,tail?}` | cron_log |

Daemon IDs are eight lowercase hex characters, job IDs are `j_` plus lowercase hex. Schedule length is bounded at 256 characters and must pass the existing minimum-60-second schedule validator; timezone is at most 128 characters. Prompt is nonblank and at most 8192 JS string characters. Booleans must be booleans. Log tail is 1–100, default 100; a job ID is mandatory to prevent global-log disclosure. Unknown params (including shell commands, cwd, paths and remote grants) are rejected.

The single supervisor-owned component serializes requests. Revision is a persisted machine-control counter, initially zero. It advances before mutation dispatch and when observed daemon/cron configuration changes, so clients must use the returned revision rather than assume increments of one. Timers, next-run values and run-log counters do not advance it. `expected_revision` is an optional nonnegative safe integer; mismatch returns `conflict` before mutation. Checks cover state observed through IPC and serialized remote operations; the existing local IPC/scheduler has no transactional compare-and-swap, so local activity can race a remote observation.

`perch-control-journal.json` persists Owner-scoped request ID keys, canonical payload digest, authorization scope and outcome. A repeated ID/payload returns the stored result (including its original revision); changed payload with the same Owner/ID returns `conflict`. Use a fresh request ID to refresh a list. The journal uses an fsynced temporary file, atomic rename and parent-directory fsync, with mode 0600 (parent-directory fsync on POSIX). It intentionally retains dedup records without automatic eviction: operators must preserve it to retain replay guarantees. Corruption disables endpoint startup rather than discarding the journal.

Pending intent and a correlated conflict outcome are durable before IPC. After a crash or uncertain IPC failure, the next valid request refreshes daemon/cron state before sealing pending outcomes. It never resends uncertain IPC, especially `cron.run`, `cron.add` or `daemon.restart`. A recorded timeout/internal failure remains the stored outcome after reconciliation; a process death before outcome recording yields the prewritten `conflict`. Refresh lists with fresh IDs and inspect logs before intentionally issuing a new mutation. This prevents duplicate dispatch, but cannot prove exactly-once execution because existing supervisor IPC has no request token.

The production IPC connect timeout is 1 second and reply timeout 5 seconds per call; relay connection has a 12-second deadline and retries after 2 seconds. Frames are bounded to 64 KiB, queued relay requests to 32, IPC replies to 4 MiB, and outbound control response JSON to 1 MiB. Errors include `unauthorized`, `forbidden`, `unsupported`, `invalid_argument`, `conflict`, `offline`, `timeout`, `internal`.

`control-capabilities.json`, `daemon-start.json`, `cron-add.json`, `control-conflict.json`, and `control-ambiguous.json` are additional golden fixtures. Tests execute all control fixtures against an isolated fake supervisor and roundtrip every control fixture. No live relay, supervisor, identity or installed files are used by these tests.


## Tool approvals (Phase 5a, extension only)

Default OFF. Operator configuration is `<cwd>/.pi/remote-pi/perch-approvals.json`
with `{ "enabled": true, "tools": ["bash"], "timeout_ms": 60000 }`. Exact tool
names only; the optional deadline is 1–300000 ms, default 60000. Missing files
opt out; malformed/unreadable existing policies fail closed. No remote policy
setter, mobile UI, push integration, or supervisor change is included.

For each selected SDK `tool_call`, only connected, authenticated, currently
paired Owners receive:

```text
perch_tool_approval_request {
  type, id, version:1, owner, session_id, tool_call_id, tool,
  args, args_digest, expires_at
}
```

`id` is a fresh unpredictable, single-use challenge; `session_id` is a fresh
process-local token reset on session start/shutdown/replacement. `owner` comes
from the authenticated relay channel, never a client identity assertion.
`args_digest` is lowercase SHA-256 hex over UTF-8 canonical JSON: recursively
sort object keys, preserve array order, JSON-encode primitive values, reject
non-JSON values. `args` is an independent snapshot of the actual validated SDK
execution arguments. `expires_at` is the server's Unix milliseconds deadline.

Reply on the same authenticated Owner channel:

```text
perch_tool_approval_decision {
  type, id, version:1, owner, session_id, tool_call_id, args_digest,
  decision:"allow"|"deny"
}
```

All bindings must exactly match. The Owner must have received that challenge
and remain paired and connected both at decision and release. The first
response from an addressed Owner consumes the challenge; invalid bindings,
explicit denial, timeout, revocation, disconnect, SDK abort/remote cancel,
relay stop, or session replacement deny. Other senders/unknown or consumed
challenge IDs are no-ops. Every request has a bounded wait; no eligible Owner
denies immediately; at most 32 pending challenges exist per extension process.
No decision ACK is emitted: this phase makes no execution-completion claim.
Ordinary legacy `approve_tool` messages remain silent no-ops.

Before releasing, the gate re-digests the original argument reference, rechecks
session and authorization, and recursively freezes validated arguments and the
SDK hook event. Later handlers cannot alter the approved execution arguments;
mutation attempts fail closed via the SDK's hook exception handling. This is
verified against installed SDK 0.79.10 and agent-core, including nested loops.
This gate covers SDK tool dispatch, not direct function calls or arbitrary code
inside other extensions. Trusted tools must tolerate immutable input arguments.

`tool-approval.json` is a golden request/decision pair consumed by TypeScript
tests, including digest verification. No client-side approval feature is implied.
