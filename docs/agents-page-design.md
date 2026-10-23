# Agents page: projects, sub-agents and session management

Status: implemented on `perch/minimal` (2026-10-23). Preview: [agents-page-preview.png](agents-page-preview.png)
(fixture from `app/test/ui/home/home_hierarchy_test.dart`, all disclosures open).

## Job
The user opens Perch to answer one question: which of my Pi sessions are doing
something, and which one do I want to talk to? Every Pi process used to be a
flat peer row: sub-agent runs (`10.15_Perch#3`), stale cached rows, generated
phone names (`10.15_Perch-000f7ed8-…`) and raw model ids, with no hierarchy.

## Information architecture
```
Agents                                   [+] [⚙]
● Relay connected
┌ 10.15_Perch          2 sessions · 1 working · 3 sub-agents ┐  project card
│ ~/…/10.15_Perch                                            │  folder (mono)
│ ● Terminal                                      13h        │  main session row
│   [Claude Opus · 5.5] Idle                                 │
│   Still running in a terminal · idle 13h                   │  idle ≥ 6h only
│   › 2 sub-agents · 1 working                               │  collapsed children
│ ● Phone session · 000f                          2m         │
│ › Offline · 1                                   Remove     │  collapsed
└────────────────────────────────────────────────────────────┘
› Not running · 3 projects                        Remove        collapsed
```
- Group by **project** = cwd folder name (across machines). The machine-grouping
  preference is retained but ignored. With >1 paired machine, rows show a machine chip.
- Card order: any working (incl. sub-agents) → any live → name. Session order:
  working → idle → checking → last activity → name.
- **Sub-agents are never peers.** They nest under the main session whose room
  launched them, behind a 44pt disclosure (“2 sub-agents · 1 working”), collapsed
  by default. Rows: 8pt dot, title, model, status. Finished (offline) sub-agent
  runs are dropped and never cached. Unlinked ones (old parent extension, parent
  gone) get a project-level “N sub-agents · parent not shown” disclosure.
- Sub-agents are excluded from counts and filter tabs; the Working filter shows
  a main session when it or any of its sub-agents works.
- Offline main sessions: inside a live project, a collapsed “Offline · N”; projects
  with nothing live go to a page-level “Not running · N projects” (collapsed,
  auto-open when nothing is live or the Offline filter is on).
- Machines with no rooms at all: “No agents running on <Mac>” card (All filter).

## Status vocabulary (main rows)
| State | Dot | Text | Meaning |
|---|---|---|---|
| Working | amber pulse | `Working` pill | turn in flight (`meta.working`) |
| Idle | green | `Idle` (+ hint after 6h) | announced, no turn |
| Checking | grey | `Checking` | presence unknown |
| Offline | hollow, dashed rail | `Offline` pill | not announced; cached row |
| Last known | stale dot | `Last known · as of 2m` | relay down; status frozen |

Trailing age: live rows = time since `idleSince` = max(relay connect
`started_at`, last synced message, last turn seen by this app run); offline rows
= last synced message or `—`. Idle hint text: terminal “Still running in a
terminal · idle 13h”; phone “Still running on <Mac> · idle 13h”. The age is a
lower-bound estimate (turns while the phone was closed are invisible).

## Naming (row titles; the project is the card header)
| Room | Title |
|---|---|
| terminal, name = folder or empty | `Terminal` |
| terminal, `<folder>#N` (2nd Pi in folder, or old-extension sub-agent) | `Terminal N` |
| phone, name `<folder>-<uuid>` | `Phone session · <uuid[0..4]>` |
| sub-agent, `<folder>#N` | `Sub-agent N` |
| any custom/renamed name | as is |

Model label (`friendlyModel`): display names (“Claude Opus · 5.5”) as is; ids lose
provider/group path, `model-`/`claude-` prefix and `-YYYYMMDD`, mono; routing
tiers (`group/std`, `fast`, `deep`, …) read as words (“Standard”). CJK display
names (e.g. `标准`) are the user's own labels and are kept.

## Protocol (backward compatible)
The relay forwards only `name/cwd/model/thinking/working` from `room_meta`
(`relay/src/handlers/peer.rs:84`), so new fields would be dropped. Kind travels in
the **room id** (`pi-extension/src/rooms.ts`):
- `session-<uuid>` phone session (unchanged); `sub.<hash12>[.<parentRoomId>]`
  sub-agent run; anything else a main session. `.` never occurs in other ids.
- Sub-agent run = `PI_SUBAGENT_CHILD=1` (async runner) or a session header with
  `parentSession` (in-process child). Checked before `PERCH_SESSION_ID`, which a
  phone session's child inherits (it used to claim and be refused the parent room).
- A main Pi exports `PERCH_ROOM_ID=<its room>` after publishing; pi-subagents
  children inherit it. Children never overwrite it.
- Old extensions: no `sub.` ids, so their children look like `Terminal N` rows
  (heuristic beyond the title would misfile genuine second terminals).
- The app never caches `sub.` rooms (`connection_manager.dart` persist).

## Management (phone → Mac)
| Row | Action | Confirm | Effect |
|---|---|---|---|
| any offline | long-press “Remove from list”; “Remove” on Offline / Not running | single: none (reversible); bulk: sheet “Remove N offline sessions?” | deletes cached room on this phone; returns if the Pi announces again; chat history kept |
| live phone session | long-press “End session…” | sheet “End this phone session?” (destructive) | perch-sessiond `sessions.stop`, then row removed; errors explain cause + fix |
| live terminal / daemon | none | — | no remote stop API exists; end it in its terminal |
| live sub-agent | open only | — | lifecycle owned by its parent run |

Live rows are never removable (they would reappear and hide a running process).

## Why `10.14_Slip` stayed online
A real `pi` (pid 78735, ttys002, since 10:34) was still running; a hidden or
detached terminal tab keeps the process and its relay room alive, so presence
was correct. The page now says so: “Still running in a terminal · idle 13h”.
A phone-side stop for terminal sessions is **not** offered: there is no
session_control/daemon API for it, and killing an interactive TUI remotely can
drop unsent input or a running tool. Revisit only as an explicit,
confirmed extension command (open question).

## Acceptance (tests)
`app/test/ui/home/home_hierarchy_test.dart`, `agent_identity_test.dart`;
`pi-extension/src/rooms.test.ts` (sub-agent ids, parent export, detection).
