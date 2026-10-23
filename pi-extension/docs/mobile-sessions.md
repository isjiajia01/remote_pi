# Mobile directory browsing and independent Pi sessions

`perch-sessiond` is a small, opt-in machine control service. It works with the
minimal extension and does not start the full supervisor, registered daemons,
cron, approvals or agent-message bridge. The service stays connected when there
are **zero Pi sessions**. The Mac must be awake and online.

Each mobile creation starts a **new** `pi --mode rpc` process in the selected
working directory, without `--continue`, with a unique history directory and
stable `session-<UUID>` relay room. Multiple sessions in the same directory are
independent. These are background Pi sessions, not cmux/Terminal tabs or shell
terminals. Existing cwd-based daemons retain their behavior.

## Local setup

Build this version of the extension (`pnpm build` in `pi-extension/`). Use the
same local identity and paired Owner storage as the existing remote-pi setup.
The older deployed extension must not be loaded alongside this one in a new
child process: check global/project Pi extension configuration for duplicates.
No project-local remote-pi config file is required or created by this service.

Create `~/.pi/remote/perch-sessions.json` locally, for example:

```json
{
  "enabled": true,
  "roots": [
    { "id": "life", "name": "Life-OS", "path": "/absolute/path/to/Life-OS" }
  ],
  "owners": {
    "<paired-Owner-public-key-in-canonical-standard-base64>": {
      "root_ids": ["life"]
    }
  }
}
```

Replace both placeholders. The Owner key is the paired phone's `remote_epk`
from local `~/.pi/remote/peers.json`, **not a private key**. It must also remain
paired. Every listed root grants that Owner the ability to start Pi in its
subdirectories, including loading trusted project instructions/extensions via
Pi's existing `--approve` startup behavior. Directory restriction governs where
sessions may start; it is not a sandbox for Pi's tools. Existing paired-peer chat
authorization is unchanged. Keep the config owner-readable/writable only.

Then run the built service in a persistent process:

```sh
node /absolute/path/to/pi-extension/dist/bin/sessiond.js
```

Or use `perch-sessiond` if this package's bin is installed. `--help` is side-effect
free. `PERCH_PI_BIN=/absolute/path/to/pi` can resolve a Pi executable not on the
service's PATH. Relay selection uses the same configuration/environment as the
extension; verify it points to the relay paired with the phone. A launchd service
may run this command with the correct PATH/relay environment and KeepAlive; this
feature does not install or change LaunchAgents automatically.

`PERCH_FULL_FEATURES=1` is **not required**. Children explicitly use minimal
mode. Do not enable the full supervisor's `perch-control.json` endpoint at the
same time: both claim the `perch-control` room. Both new entry points reject that
configuration. Running chat sessions and the existing relay can stay up.

The exclusive `~/.pi/remote/perch-sessiond.lock` prevents two writers. SIGINT or
SIGTERM stops this service's children and removes the lock. After a hard crash,
inspect the PID recorded in the lock and any surviving Pi children before
manually removing a stale lock; the service deliberately does not steal it.

## Wire contract for mobile

Use the existing authenticated peer relay envelope, addressed to the selected
machine's **`perch-control`** room. A chat room need not be online. This control
room must not be displayed as a chat session. Negotiate after connecting or
reconnecting:

```json
{ "type": "perch_capabilities_get", "id": "unique-cap-id" }
```

Response: `perch_capabilities_result`, `version: 1`, `scope: "supervisor"`,
`ack_semantics: "delivery_only"`, methods below. `limits` retains the compatible
shape `{ "max_prompt_chars": 0, "max_log_entries": 0 }`; cron is unsupported.

Requests use the existing shape, **without `expected_revision`**:

```json
{
  "type": "perch_request", "id": "unique-request-id", "version": 1,
  "method": "sessions.create",
  "params": { "root_id": "life", "relative_path": "10-19 Personal/My Project" }
}
```

Successful replies are:

```json
{
  "type": "perch_result", "id": "unique-request-id", "version": 1,
  "method": "sessions.create",
  "result": { "scope": "supervisor", "revision": 0, "data": {} }
}
```

`data` by method:

| Method | Params | Result data |
| --- | --- | --- |
| `directories.roots` | `{}` | `{roots: [{id, name}]}`; no absolute host paths |
| `directories.list` | `{root_id, relative_path, offset?}` | `{root_id, relative_path, directories: [{name, relative_path}], next_offset: number|null}` |
| `sessions.create` | `{root_id, relative_path}` | Session object below |
| `sessions.get` | `{session_id}` | Session object with current process state |
| `sessions.stop` | `{session_id}` | Session object after stopping; safe to repeat |

Root directory is `relative_path: ""`. Paths use `/`, preserve spaces and
Unicode; no shell quoting or home expansion. Absolute paths, `.`/`..` components,
backslashes and symlinks escaping the real root are refused. Inside-root symlink
directories may be listed. Listings sort names, return up to 100 directories per
page; `offset` defaults to zero. A directory exceeding 5000 filesystem entries
returns `invalid_argument` rather than an incomplete, misleading list. Directory
changes between pages may shift offsets; refresh from zero. Only existing
directories can be selected; there is no create-folder or file-content API.

Session object:

```json
{
  "session_id": "12345678-1234-4234-8234-123456789abc",
  "room_id": "session-12345678-1234-4234-8234-123456789abc",
  "root_id": "life",
  "relative_path": "10-19 Personal/My Project",
  "name": "My-Project-12345678-1234-4234-8234-123456789abc",
  "state": "starting"
}
```

States are `starting`, `running`, `stopped`, `failed`, `interrupted`; `error` is
optional descriptive text. `running` means the OS process is running, **not that
its relay/chat is ready**. After creation, wait for exactly the returned
`room_id` to appear online on the selected machine, then open that chat. Poll
`sessions.get` while waiting to detect exit/startup failure. If the room never
appears, show a connection/startup error and allow stopping the process. Never
interpret the relay's delivery acknowledgment as creation success.

Keep a create request's ID and exact params across timeout, reconnect and retry.
The same Owner + request ID returns the same session, never creates another;
changing its directory returns `conflict`. A deliberate second new session uses
a **new** request ID. Persist a pending request on the phone before sending if
retry must survive app termination. `sessions.get` and `sessions.stop` are only
available to that creating Owner with a current root grant.

Errors use existing `perch_error.error.{code,message}`: `unauthorized`,
`forbidden`, `unsupported`, `invalid_argument`, `conflict`, `offline`, `internal`.
A missing service may surface as a client timeout. Display an actionable local
setup message; do not silently fall back to an existing chat. Grants are reread
on every request/replay. Revoking grants blocks further control, but does not
kill an already running Pi session or change existing pairing/chat policy.

## Lifecycle and recovery

New sessions do not enter the old per-cwd daemon registry. No restart or resume
is automatic: crashes are `failed`; orderly service shutdown stops children.
History remains in `~/.pi/remote/mobile-sessions/<session_id>/`. A service restart
marks previously live/uncertain journal entries `interrupted` and does not launch
them again. After a hard crash an old process may remain online; mobile may use
its returned room, but this new service cannot stop an orphan and instructs the
operator to stop it locally. History can be opened locally using Pi's session
selection options; mobile history-resume is outside this feature.

A durable, fsynced intent in `perch-sessions-journal.json` precedes every spawn.
It is kept for replay protection, including failed/stopped sessions. Do not delete
it while a phone might retry an old request. The service refuses a corrupt
journal. Limits are 16 active children and 10,000 retained requests; hitting a
limit gives `conflict`. Stop unused sessions to free active capacity; journal
maintenance is a local operation after outstanding mobile requests are resolved.

Renaming a mobile session changes only its inline config, preserves its stable
room and does not overwrite the project's remote-pi defaults. The old in-chat
New Context daemon fallback cannot restart an independent session; when Pi lacks
a command context it instructs the user to create a new session from Home.

Path checks use realpath immediately before spawning and reject symlink escapes.
This is a remote input boundary, not protection against a malicious local user
racing filesystem mutations with the same OS account. No shell command string is
constructed from mobile input.

## Mobile entry and implementation handoff

The minimal phone app exposes **New session** (+) on Agents whenever a machine
is paired, including when it has no chat rooms. Choose the machine, authorized
root and folder, then create. The phone saves the request ID, machine and exact
folder in secure storage before dispatch, restores it after reopening, and waits
for the returned room before opening chat. Retry recovers that same request.
Failed/stopped requests can be dismissed; running sessions can be stopped from
the pending creation screen. Interrupted orphan recovery remains a local task.

Implementation provenance: the Designer mobile lane did not execute or produce
changes because the provider returned HTTP 429 (Claude session limit). There was
no automatic model fallback, following the fixed Designer model/no-fallback rule
and the requirement to stop on subagent infrastructure failure. The user then
explicitly authorized Main to implement the mobile component and send it to an
independent Reviewer. Backend work was retained; the failed lane was not rerun.

## Focused verification

```sh
pnpm typecheck
pnpm exec vitest run src/daemon/session_control.test.ts src/daemon/perch_control_relay.test.ts src/daemon/rpc_child.test.ts src/rooms.test.ts src/session/local_config.test.ts src/minimal.test.ts
pnpm build
node dist/bin/sessiond.js --help
```

Tests use temporary directories and fake children or tiny local executable stubs;
they do not launch Pi, call a model, use real pairing secrets or change deployment.
