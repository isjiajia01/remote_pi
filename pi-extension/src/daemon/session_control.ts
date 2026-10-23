import { createHash, randomUUID } from "node:crypto";
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, realpathSync, renameSync, statSync, writeFileSync } from "node:fs";
import { opendir } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, sep } from "node:path";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { perchError, type PerchClientMessage, type PerchServerMessage } from "../protocol/perch.js";
import { RpcChild, type RpcChildOptions } from "./rpc_child.js";
import { sanitizeSegment } from "../session/local_config.js";

export const SESSION_METHODS = ["directories.roots", "directories.list", "sessions.create", "sessions.get", "sessions.stop"] as const;
const ROOT_ID = /^[a-zA-Z0-9_-]{1,64}$/;
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const MAX_RECORDS = 10_000;
const MAX_ACTIVE = 16;
const PAGE_SIZE = 100;
const MAX_DIRECTORY_ENTRIES = 5000;
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
const only = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).every((k) => keys.includes(k));
export type SessionRoot = { id: string; name: string; path: string };
export type SessionControlConfig = { enabled: true; roots: SessionRoot[]; owners: Record<string, { root_ids: string[] }> };

/** Local-only explicit opt-in. Invalid config never grants partial access. Reloaded for each request. */
export function loadSessionControlConfig(path: string): SessionControlConfig | undefined {
  try {
    const c: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!record(c) || !only(c, ["enabled", "roots", "owners"]) || c.enabled !== true ||
        !Array.isArray(c.roots) || !c.roots.length || c.roots.length > 32 || !record(c.owners)) return;
    const roots: SessionRoot[] = [];
    for (const r of c.roots) {
      if (!record(r) || !only(r, ["id", "name", "path"]) || typeof r.id !== "string" || !ROOT_ID.test(r.id) ||
          roots.some((root) => root.id === r.id) || typeof r.name !== "string" || !r.name.trim() || r.name.length > 128 ||
          typeof r.path !== "string" || !isAbsolute(r.path)) return;
      // Store the administrator's path; realpath is rechecked at point of use.
      roots.push({ id: r.id, name: r.name, path: r.path });
    }
    const owners: SessionControlConfig["owners"] = {};
    for (const [key, value] of Object.entries(c.owners)) {
      if (canonicalizeEd25519PublicKey(key) !== key || !record(value) || !only(value, ["root_ids"]) ||
          !Array.isArray(value.root_ids) || !value.root_ids.every((id) => typeof id === "string" && roots.some((r) => r.id === id))) return;
      owners[key] = { root_ids: value.root_ids as string[] };
    }
    return { enabled: true, roots, owners };
  } catch { return; }
}

class ControlError extends Error {
  constructor(readonly code: "forbidden" | "invalid_argument" | "conflict" | "offline", message: string) { super(message); }
}

/** Reject lexical traversal as well as canonical symlink escapes. Never accept a shell/path expression. */
export function resolveSessionDirectory(root: SessionRoot, input: unknown): string {
  if (typeof input !== "string" || input.length > 4096 || input.includes("\0") || input.includes("\\") ||
      isAbsolute(input) || input.split("/").some((part) => part === ".." || part === ".") || /^[A-Za-z]:/.test(input)) {
    throw new ControlError("invalid_argument", "Expected a relative directory beneath the authorized root");
  }
  let base: string;
  let target: string;
  try {
    base = realpathSync(root.path);
    target = realpathSync(join(base, input));
    if (!statSync(target).isDirectory()) throw new Error("not directory");
  } catch { throw new ControlError("invalid_argument", "Directory is unavailable"); }
  const rel = relative(base, target);
  if (rel === ".." || rel.startsWith(`..${sep}`) || isAbsolute(rel)) throw new ControlError("forbidden", "Directory is outside the authorized root");
  return target;
}

type SessionState = "starting" | "running" | "stopped" | "failed" | "interrupted";
export type SessionView = { session_id: string; room_id: string; root_id: string; relative_path: string;
  name: string; state: SessionState; error?: string };
type Entry = { owner: string; digest: string; view: SessionView };
type Journal = { version: 1; entries: Record<string, Entry> };
export type SessionChild = Pick<RpcChild, "spawn" | "stop" | "state" | "on">;
export interface SessionControlOptions {
  configPath: string;
  journalPath: string;
  sessionsPath: string;
  extensionPath: string;
  piBin?: string;
  isPaired: (owner: string) => Promise<boolean>;
  createChild?: (options: RpcChildOptions) => SessionChild;
}

/** One machine service, independent of all children. No auto-restart, cwd registry, or cron. */
export class SessionControl {
  private readonly journal: Journal;
  private readonly children = new Map<string, SessionChild>();
  private readonly negotiated = new Set<string>();
  private queue: Promise<unknown> = Promise.resolve();
  private closing = false;

  constructor(private readonly options: SessionControlOptions) {
    this.journal = existsSync(options.journalPath) ? JSON.parse(readFileSync(options.journalPath, "utf8")) : { version: 1, entries: {} };
    if (!record(this.journal) || this.journal.version !== 1 || !record(this.journal.entries) ||
        Object.keys(this.journal.entries).length > MAX_RECORDS || Object.entries(this.journal.entries).some(([key, e]) =>
          !/^[a-f0-9]{64}$/.test(key) || !record(e) || typeof e.owner !== "string" || typeof e.digest !== "string" ||
          !/^[a-f0-9]{64}$/.test(e.digest) || !record(e.view) || !SESSION_ID.test(e.view.session_id as string) ||
          e.view.room_id !== `session-${e.view.session_id}` || typeof e.view.root_id !== "string" ||
          typeof e.view.relative_path !== "string" || typeof e.view.name !== "string" ||
          !["starting", "running", "stopped", "failed", "interrupted"].includes(e.view.state as string))) {
      throw new Error("Invalid session journal; refusing to erase replay protection");
    }
    // A crash may leave children alive. Never re-spawn an uncertain request.
    // Their room may still be online; mobile must inspect presence before acting.
    for (const e of Object.values(this.journal.entries)) {
      if (e.view.state === "starting" || e.view.state === "running") {
        e.view.state = "interrupted";
        e.view.error = "Control service restarted; session was not restarted. Check its room before creating another.";
      }
    }
    this.save();
  }

  disconnect(): void { this.negotiated.clear(); }

  private save(): void {
    mkdirSync(dirname(this.options.journalPath), { recursive: true, mode: 0o700 });
    const tmp = `${this.options.journalPath}.${randomUUID()}.tmp`;
    const fd = openSync(tmp, "wx", 0o600);
    try { writeFileSync(fd, JSON.stringify(this.journal)); fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(tmp, this.options.journalPath);
    if (process.platform !== "win32") {
      const dir = openSync(dirname(this.options.journalPath), "r");
      try { fsyncSync(dir); } finally { closeSync(dir); }
    }
  }

  handle(owner: string, msg: PerchClientMessage): Promise<PerchServerMessage> {
    const work = this.queue.then(() => this.execute(owner, msg));
    this.queue = work.catch(() => {});
    return work.catch((e) => perchError(typeof msg.id === "string" ? msg.id : "",
      e instanceof ControlError ? e.code : "internal", e instanceof ControlError ? e.message : "Session control failed"));
  }

  private async authorized(owner: string): Promise<{ config: SessionControlConfig; rootIds: string[] }> {
    if (!await this.options.isPaired(owner)) throw new ControlError("forbidden", "Sender is not a paired Owner");
    const config = loadSessionControlConfig(this.options.configPath);
    const grant = config?.owners[owner];
    if (!config || !grant) throw new ControlError("forbidden", "Session creation is not enabled for this Owner");
    return { config, rootIds: grant.root_ids };
  }

  private async root(owner: string, id: unknown): Promise<SessionRoot> {
    const { config, rootIds } = await this.authorized(owner);
    const root = config.roots.find((r) => r.id === id && rootIds.includes(r.id));
    if (!root) throw new ControlError("forbidden", "Root is not authorized");
    return root;
  }

  private view(entry: Entry): SessionView {
    const child = this.children.get(entry.view.session_id);
    // Process running is not relay readiness. Clients must await this exact room.
    if (child?.state === "running" && entry.view.state === "starting") entry.view.state = "running";
    return { ...entry.view };
  }

  private async execute(owner: string, msg: PerchClientMessage): Promise<PerchServerMessage> {
    if (!await this.options.isPaired(owner)) return perchError(msg.id, "unauthorized", "Sender is not a paired Owner");
    const { config, rootIds } = await this.authorized(owner);
    if (this.closing) throw new ControlError("offline", "Control service is stopping");
    if (typeof msg.id !== "string" || !msg.id || msg.id.length > 256) throw new ControlError("invalid_argument", "Invalid request id");
    if (msg.type === "perch_capabilities_get") {
      this.negotiated.add(owner);
      return { type: "perch_capabilities_result", id: msg.id, version: 1, scope: "supervisor",
        methods: SESSION_METHODS, ack_semantics: "delivery_only", limits: { max_prompt_chars: 0, max_log_entries: 0 } };
    }
    if (!this.negotiated.has(owner) || msg.version !== 1 || !SESSION_METHODS.includes(msg.method as typeof SESSION_METHODS[number])) {
      return perchError(msg.id, "unsupported", "Negotiate session control capabilities first");
    }
    if (!only(msg as unknown as Record<string, unknown>, ["type", "id", "version", "method", "params"]) || !record(msg.params)) {
      throw new ControlError("invalid_argument", "Invalid request fields");
    }
    const p = msg.params;
    let data: unknown;
    let resultRootId: string | undefined;
    if (msg.method === "directories.roots") {
      if (!only(p, [])) throw new ControlError("invalid_argument", "Invalid roots params");
      data = { roots: config.roots.filter((r) => rootIds.includes(r.id)).map(({ id, name }) => ({ id, name })) };
    } else if (msg.method === "directories.list" || msg.method === "sessions.create") {
      const creating = msg.method === "sessions.create";
      if (!only(p, creating ? ["root_id", "relative_path"] : ["root_id", "relative_path", "offset"]) ||
          typeof p.root_id !== "string" || typeof p.relative_path !== "string") throw new ControlError("invalid_argument", "Invalid directory params");
      const root = await this.root(owner, p.root_id);
      resultRootId = root.id;
      if (creating) data = await this.create(owner, msg.id, root, p.relative_path);
      else {
        const path = resolveSessionDirectory(root, p.relative_path);
        const offset = p.offset ?? 0;
        if (!Number.isSafeInteger(offset) || (offset as number) < 0 || (offset as number) > MAX_DIRECTORY_ENTRIES) {
          throw new ControlError("invalid_argument", "Invalid directory offset");
        }
        const directories: { name: string; relative_path: string }[] = [];
        let seen = 0;
        for await (const entry of await opendir(path)) {
          if (++seen > MAX_DIRECTORY_ENTRIES) throw new ControlError("invalid_argument", "Directory exceeds 5000 entries; choose a smaller root locally");
          if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
          const rel = [p.relative_path, entry.name].filter(Boolean).join("/");
          try { resolveSessionDirectory(root, rel); } catch { continue; }
          directories.push({ name: entry.name, relative_path: rel });
        }
        directories.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
        await this.root(owner, root.id);
        const start = offset as number;
        data = { root_id: root.id, relative_path: p.relative_path, directories: directories.slice(start, start + PAGE_SIZE),
          next_offset: start + PAGE_SIZE < directories.length ? start + PAGE_SIZE : null };
      }
    } else {
      if (!only(p, ["session_id"]) || typeof p.session_id !== "string" || !SESSION_ID.test(p.session_id)) {
        throw new ControlError("invalid_argument", "Invalid session id");
      }
      const entry = Object.values(this.journal.entries).find((e) => e.owner === owner && e.view.session_id === p.session_id);
      if (!entry) throw new ControlError("forbidden", "Session is not owned by this Owner");
      await this.root(owner, entry.view.root_id);
      resultRootId = entry.view.root_id;
      if (msg.method === "sessions.stop") {
        const child = this.children.get(entry.view.session_id);
        if (!child && entry.view.state === "interrupted") throw new ControlError("conflict", "This service no longer owns the process; stop it locally");
        if (child) await child.stop();
        entry.view.state = "stopped";
        delete entry.view.error;
        this.save();
      }
      data = this.view(entry);
    }
    // Revocation during filesystem or process work must not disclose a result.
    if (resultRootId) await this.root(owner, resultRootId);
    else {
      const latest = await this.authorized(owner);
      data = { roots: latest.config.roots.filter((r) => latest.rootIds.includes(r.id)).map(({ id, name }) => ({ id, name })) };
    }
    return { type: "perch_result", id: msg.id, version: 1, method: msg.method,
      result: { scope: "supervisor", revision: 0, data } };
  }

  private async create(owner: string, requestId: string, root: SessionRoot, relativePath: string): Promise<SessionView> {
    const hash = (s: string) => createHash("sha256").update(s).digest("hex");
    const key = hash(JSON.stringify([owner, requestId]));
    const digest = hash(JSON.stringify([root.id, relativePath]));
    const prior = this.journal.entries[key];
    if (prior) {
      if (prior.digest !== digest) throw new ControlError("conflict", "Request id was already used for a different directory");
      return this.view(prior);
    }
    if (Object.keys(this.journal.entries).length >= MAX_RECORDS || this.children.size >= MAX_ACTIVE) {
      throw new ControlError("conflict", "Session capacity reached; stop unused sessions or maintain the journal locally");
    }
    const cwd = resolveSessionDirectory(root, relativePath);
    const sessionId = randomUUID();
    const name = `${sanitizeSegment(basename(cwd))?.slice(0, 48) || "Pi"}-${sessionId}`;
    const entry: Entry = { owner, digest, view: { session_id: sessionId, room_id: `session-${sessionId}`,
      root_id: root.id, relative_path: relativePath, name, state: "starting" } };
    // Durable intent BEFORE spawn: crash recovery never launches this request a second time.
    this.journal.entries[key] = entry;
    this.save();
    try {
      const currentRoot = await this.root(owner, root.id);
      if (resolveSessionDirectory(currentRoot, relativePath) !== cwd) throw new Error("Directory changed before launch");
      const sessionDir = join(this.options.sessionsPath, sessionId);
      mkdirSync(sessionDir, { recursive: true, mode: 0o700 });
      const child = (this.options.createChild ?? ((opts) => new RpcChild(opts)))({
        extensionPath: this.options.extensionPath, piBin: this.options.piBin, cwd,
        freshSession: true, sessionDir, config: { agent_name: name, auto_start_relay: true },
        env: { PERCH_SESSION_ID: sessionId, PERCH_FULL_FEATURES: "0" },
      });
      child.on("exit", (event: { isCrash: boolean }) => {
        this.children.delete(sessionId);
        entry.view.state = event.isCrash ? "failed" : "stopped";
        if (event.isCrash) entry.view.error = "Pi process exited or could not start; check the control service log";
        try { this.save(); } catch { this.closing = true; }
      });
      this.children.set(sessionId, child);
      child.spawn();
    } catch {
      this.children.delete(sessionId);
      entry.view.state = "failed";
      entry.view.error = "Pi could not start; check directory permissions and the control service log";
      this.save();
    }
    return { ...entry.view };
  }

  async close(): Promise<void> {
    this.closing = true;
    await this.queue;
    await Promise.all([...this.children.values()].map((child) => child.stop()));
  }
}
