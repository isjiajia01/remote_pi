import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import { defaultAgentName } from "./session/local_config.js";

/**
 * Env var a MAIN Pi exports with its published room id. Sub-agent runs
 * (pi-subagents async runners or in-process children) inherit it and announce
 * it as their parent. Sub-agent runs never write it.
 */
export const PARENT_ROOM_ENV = "PERCH_ROOM_ID";
const ROOM_TOKEN = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * True for pi-subagents child runs: the async runner sets PI_SUBAGENT_CHILD=1;
 * in-process children carry `parentSession` in their session header.
 */
export function isSubagentRun(header?: { parentSession?: unknown } | null): boolean {
  return process.env["PI_SUBAGENT_CHILD"] === "1" || Boolean(header?.parentSession);
}

/**
 * Room kind travels IN the room id because the relay forwards only a fixed
 * room_meta field set (name/cwd/model/thinking/working) and drops new fields:
 *   `session-<uuid>`              phone-created (perch-sessiond) session
 *   `sub.<hash12>[.<parentRoom>]` sub-agent run; parent omitted when unknown
 *   anything else                 main terminal/daemon session
 * '.' never occurs in main/mobile ids, so the parent is unambiguous.
 */
export function subagentRoomIdFor(cwd: string, name?: string): string {
  const parent = process.env[PARENT_ROOM_ENV];
  const own = roomIdFor(cwd, name);
  return parent && ROOM_TOKEN.test(parent) ? `sub.${own}.${parent}` : `sub.${own}`;
}

/** Called once a main room is published so later sub-agent runs can link to it. */
export function exportParentRoom(roomId: string, subagent: boolean): void {
  if (!subagent && ROOM_TOKEN.test(roomId)) process.env[PARENT_ROOM_ENV] = roomId;
}

/** Mobile-created sessions keep their independent room even after renaming. */
export function activeRoomIdFor(
  cwd: string,
  name?: string,
  subagent = process.env["PI_SUBAGENT_CHILD"] === "1",
): string {
  // Before PERCH_SESSION_ID: a sub-agent of a phone session inherits that env
  // var and would otherwise claim (and be refused) its parent's room.
  if (subagent) return subagentRoomIdFor(cwd, name);
  const session = process.env["PERCH_SESSION_ID"];
  return session && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(session)
    ? `session-${session}` : roomIdFor(cwd, name);
}

/**
 * Deterministic room id derived from a cwd. Two Pi processes in the same
 * directory produce the same id; different cwds produce different ids
 * (with cryptographic-strength collision resistance). Symlinks are resolved
 * via `realpath` so `/a` and `/symlink-to-a` map to the same room.
 *
 * Format: first 12 chars of base64url(sha256(realpath)).
 */
export function roomIdForCwd(cwd: string): string {
  let target: string;
  try {
    target = realpathSync(cwd);
  } catch {
    // cwd doesn't exist (unlikely in production) — fallback to raw path.
    target = cwd;
  }
  return createHash("sha256").update(target).digest("base64url").slice(0, 12);
}

/**
 * THE single derivation of the App↔Pi `room_id` (plan/41) — keyed by
 * `(cwd, name)` so several agents in the SAME folder get distinct rooms (the
 * app then renders one tile per agent instead of merging them into one).
 *
 * Default-preserving: when `name` is absent OR equals `defaultAgentName(cwd)`
 * (an agent with no custom `agent_name`), it returns the LEGACY `roomIdForCwd`
 * EXACTLY — so a single unnamed agent's existing conversation is NOT re-keyed
 * on upgrade. A custom or `#N`-suffixed name → a name-scoped id (same formula
 * the cwd-lock uses).
 *
 * Using the ASSIGNED leaf name (the broker's `#N` on collision) disambiguates
 * even two unnamed agents: the 1st stays `folder` (== default → legacy room),
 * the 2nd becomes `folder#2` (≠ default → name-scoped room).
 *
 * INVARIANT: every callsite that derives the App↔Pi room for the same agent
 * MUST go through this function — otherwise the app would pair on a room the
 * Pi never announces.
 */
export function roomIdFor(cwd: string, name?: string): string {
  if (!name || name === defaultAgentName(cwd)) return roomIdForCwd(cwd);
  let target: string;
  try {
    target = realpathSync(cwd);
  } catch {
    target = cwd;
  }
  // NUL separator (U+0000): impossible in a POSIX path and stripped from any
  // sanitized name, so the cwd/name boundary is unambiguous.
  const sep = String.fromCharCode(0);
  return createHash("sha256").update(target + sep + name).digest("base64url").slice(0, 12);
}
