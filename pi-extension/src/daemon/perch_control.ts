import { createHash, randomUUID } from "node:crypto";
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { canonicalizeEd25519PublicKey } from "../mesh/encoding.js";
import { perchError, type PerchClientMessage, type PerchServerMessage } from "../protocol/perch.js";
import { callSupervisor, SupervisorOfflineError, SupervisorReplyError, type SupervisorCallOptions } from "./client.js";
import type { ControlRequest, CronJobView, DaemonInfo } from "./control_protocol.js";
import { controlOperation, PERCH_CONTROL_LIMITS, PERCH_CONTROL_METHODS, validDaemonId, type PerchControlMethod } from "./perch_control_protocol.js";

type Grant = { operations: PerchControlMethod[]; daemon_ids: string[] };
export type PerchControlConfig = { enabled: boolean; owners: Record<string, Grant> };
const record = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
const only = (v: Record<string, unknown>, keys: string[]) => Object.keys(v).every((k) => keys.includes(k));

/** Invalid or unknown-field config fails closed. This file is never writable via the wire protocol. */
export function loadPerchControlConfig(path: string): PerchControlConfig {
  const denied: PerchControlConfig = { enabled: false, owners: {} };
  try {
    const c: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!record(c) || !only(c, ["enabled", "owners"]) || c.enabled !== true || !record(c.owners)) return denied;
    const owners: Record<string, Grant> = {};
    for (const [key, g] of Object.entries(c.owners)) {
      if (canonicalizeEd25519PublicKey(key) !== key || !record(g) || !only(g, ["operations", "daemon_ids"]) ||
          !Array.isArray(g.operations) || !g.operations.every((op) => PERCH_CONTROL_METHODS.includes(op)) ||
          !Array.isArray(g.daemon_ids) || !g.daemon_ids.every(validDaemonId)) return denied;
      owners[key] = { operations: g.operations, daemon_ids: g.daemon_ids };
    }
    return { enabled: true, owners };
  } catch { return denied; }
}

type Entry = { digest: string; daemonId?: string; visibleDaemonIds?: string[]; pending: boolean; outcome?: PerchServerMessage };
type Journal = { version: 1; revision: number; fingerprint: string; entries: Record<string, Entry> };
type Snapshot = { daemons: DaemonInfo[]; jobs: CronJobView[] };
export interface PerchControlOptions {
  configPath: string;
  journalPath: string;
  /** Must consult current local paired-Owner storage, never a remote claim. */
  isPaired: (owner: string) => Promise<boolean>;
  ipc?: (request: ControlRequest) => Promise<unknown>;
  supervisor?: SupervisorCallOptions;
}
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (record(value)) return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  return JSON.stringify(value);
}
const digest = (value: unknown) => createHash("sha256").update(canonical(value)).digest("hex");

/** One writer, owned by the supervisor process. All reads and mutations share the same queue.
 * A durable pending record precedes IPC. Recovery observes state and seals the stored
 * failure/conflict; it never resends an uncertain operation, including cron.run/add/restart.
 */
export class PerchControl {
  private readonly journal: Journal;
  private queue: Promise<unknown> = Promise.resolve();
  private readonly negotiated = new Set<string>();
  private readonly ipc: (request: ControlRequest) => Promise<unknown>;

  constructor(private readonly options: PerchControlOptions) {
    this.ipc = options.ipc ?? ((request) => callSupervisor(request, options.supervisor));
    if (existsSync(options.journalPath)) {
      // Corruption must fail startup rather than erase replay protection.
      const j = JSON.parse(readFileSync(options.journalPath, "utf8")) as Journal;
      if (j.version !== 1 || !Number.isSafeInteger(j.revision) || j.revision < 0 ||
          typeof j.fingerprint !== "string" || !record(j.entries) || Object.values(j.entries).some((e) =>
            !record(e) || typeof e.digest !== "string" || !/^[a-f0-9]{64}$/.test(e.digest) ||
            typeof e.pending !== "boolean" || (e.daemonId !== undefined && !validDaemonId(e.daemonId)) ||
            (e.visibleDaemonIds !== undefined && (!Array.isArray(e.visibleDaemonIds) || !e.visibleDaemonIds.every(validDaemonId))) ||
            !record(e.outcome) || typeof e.outcome.id !== "string" || e.outcome.version !== 1 ||
            !["perch_result", "perch_error"].includes(e.outcome.type as string))) {
        throw new Error("Invalid Perch control journal");
      }
      this.journal = j;
    } else this.journal = { version: 1, revision: 0, fingerprint: "", entries: {} };
  }

  disconnect(): void { this.negotiated.clear(); }

  handle(owner: string, msg: PerchClientMessage): Promise<PerchServerMessage> {
    const pending = this.queue.then(() => this.execute(owner, msg));
    this.queue = pending.catch(() => {});
    return pending.catch(() => perchError(typeof msg.id === "string" ? msg.id : "", "internal", "Control request failed"));
  }

  private save(): void {
    const path = this.options.journalPath;
    mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    const tmp = `${path}.${randomUUID()}.tmp`;
    const fd = openSync(tmp, "wx", 0o600);
    try { writeFileSync(fd, JSON.stringify(this.journal)); fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(tmp, path);
    // Windows does not support opening/fsyncing directories through node:fs.
    if (process.platform !== "win32") {
      const dir = openSync(dirname(path), "r");
      try { fsyncSync(dir); } finally { closeSync(dir); }
    }
  }

  private grant(owner: string, method?: string): Grant | undefined {
    const c = loadPerchControlConfig(this.options.configPath);
    const g = c.enabled ? c.owners[owner] : undefined;
    return g && (!method || g.operations.includes(method as PerchControlMethod)) ? g : undefined;
  }

  private async snapshot(): Promise<Snapshot> {
    const daemons = await this.ipc({ op: "list" }) as { daemons: DaemonInfo[] };
    const jobs = await this.ipc({ op: "cron_list" }) as { jobs: CronJobView[] };
    if (!Array.isArray(daemons.daemons) || !Array.isArray(jobs.jobs)) throw new Error("Invalid supervisor snapshot");
    const snapshot = { daemons: daemons.daemons, jobs: jobs.jobs };
    // Ignore timers/next-run/log counters; revision represents control state, not elapsed time.
    const fingerprint = digest({ daemons: snapshot.daemons.map(({ id, state, pid, restart_count }) =>
      ({ id, state, pid: pid ?? null, restart_count: restart_count ?? null })), jobs: snapshot.jobs.map((j) =>
      ({ id: j.id, daemon_id: j.daemon_id, schedule: j.schedule, prompt: j.prompt, tz: j.tz ?? null,
        enabled: j.enabled, wake: j.wake, catchup: j.catchup, skip_if_busy: j.skip_if_busy })) });
    if (this.journal.fingerprint !== fingerprint) {
      if (this.journal.fingerprint) this.journal.revision++;
      this.journal.fingerprint = fingerprint;
      this.save();
    }
    return snapshot;
  }

  private async execute(owner: string, msg: PerchClientMessage): Promise<PerchServerMessage> {
    const id = typeof msg.id === "string" ? msg.id : "";
    const error = (code: Parameters<typeof perchError>[1], text: string) => perchError(id, code, text);
    if (!await this.options.isPaired(owner)) return error("unauthorized", "Sender is not a paired Owner");
    if (!id || id.length > 256) return error("invalid_argument", "Invalid request id");
    const method = msg.type === "perch_request" ? msg.method : undefined;
    if (method !== undefined && !PERCH_CONTROL_METHODS.includes(method as PerchControlMethod)) {
      return error("unsupported", "Unsupported control method");
    }
    let grant = this.grant(owner, method);
    if (!grant) return error("forbidden", "No local operation grant");
    if (msg.type === "perch_capabilities_get") {
      this.negotiated.add(owner);
      return { type: "perch_capabilities_result", id, version: 1, scope: "supervisor",
        methods: grant.operations, ack_semantics: "delivery_only", limits: PERCH_CONTROL_LIMITS };
    }
    if (!this.negotiated.has(owner)) return error("unsupported", "Negotiate control capabilities first");
    if (msg.version !== 1 || !PERCH_CONTROL_METHODS.includes(msg.method as PerchControlMethod)) {
      return error("unsupported", "Unsupported control version or method");
    }
    if (!only(msg as unknown as Record<string, unknown>, ["type", "id", "version", "method", "params", "expected_revision"]) ||
        (msg.expected_revision !== undefined && (!Number.isSafeInteger(msg.expected_revision) || msg.expected_revision < 0))) {
      return error("invalid_argument", "Invalid request fields or revision");
    }
    const operation = controlOperation(msg.method, msg.params);
    if (!operation) return error("invalid_argument", "Invalid method params");
    const key = digest([owner, id]);
    const payloadDigest = digest(msg);
    let entry = this.journal.entries[key];
    if (entry && entry.digest !== payloadDigest) return error("conflict", "Request id already used with different payload");
    let daemonId = entry?.daemonId ?? operation.daemonId;
    if ((daemonId && !grant.daemon_ids.includes(daemonId)) ||
        entry?.visibleDaemonIds?.some((d) => !grant!.daemon_ids.includes(d))) return error("forbidden", "Daemon is not locally granted");
    // Replays still require current pairing and grants, including after cron.remove.
    if (entry?.outcome && !entry.pending) return entry.outcome;
    let dispatching = false;
    try {
      const snapshot = await this.snapshot();
      // Successful observation is required before sealing any crash/timeout ambiguity.
      for (const pending of Object.values(this.journal.entries)) {
        if (pending.pending) {
          pending.pending = false;
          // The prewritten outcome carries this entry's original request id.
          if (!pending.outcome) throw new Error("Missing pending outcome");
        }
      }
      // Pending records retain their own id in the prewritten conflict outcome.
      this.save();
      if (entry?.outcome) return entry.outcome;
      if (operation.jobId) {
        const job = snapshot.jobs.find((j) => j.id === operation.jobId);
        if (!job) return error("invalid_argument", "Unknown cron job");
        daemonId = job.daemon_id;
      }
      // Recheck both authority sources immediately before any effect.
      if (!await this.options.isPaired(owner)) return error("unauthorized", "Sender is not a paired Owner");
      grant = this.grant(owner, msg.method);
      if (!grant || (daemonId && !grant.daemon_ids.includes(daemonId))) return error("forbidden", "No local operation or daemon grant");
      if (msg.expected_revision !== undefined && msg.expected_revision !== this.journal.revision) {
        const outcome = error("conflict", `Expected revision differs from ${this.journal.revision}`);
        this.journal.entries[key] = { digest: payloadDigest, daemonId, pending: false, outcome };
        this.save();
        return outcome;
      }
      entry = { digest: payloadDigest, daemonId,
        visibleDaemonIds: daemonId ? undefined : [...grant.daemon_ids], pending: true,
        outcome: error("conflict", "Previous IPC outcome uncertain; state reconciled, inspect fresh lists before a new request") };
      this.journal.entries[key] = entry;
      if (operation.mutation) this.journal.revision++;
      this.save();
      let data: unknown;
      if (msg.method === "daemon.list") data = { daemons: snapshot.daemons.filter((d) => grant!.daemon_ids.includes(d.id)) };
      else if (msg.method === "cron.list") data = { jobs: snapshot.jobs.filter((j) => grant!.daemon_ids.includes(j.daemon_id)) };
      else {
        dispatching = true;
        data = await this.ipc(operation.request);
        dispatching = false;
      }
      if (operation.mutation) await this.snapshot();
      const outcome: PerchServerMessage = { type: "perch_result", id, version: 1, method: msg.method,
        result: { scope: "supervisor", revision: this.journal.revision, data } };
      entry.pending = false;
      entry.outcome = outcome;
      this.save();
      if (!await this.options.isPaired(owner)) return error("unauthorized", "Sender is not a paired Owner");
      const currentGrant = this.grant(owner, msg.method);
      if (!currentGrant || (daemonId ? !currentGrant.daemon_ids.includes(daemonId) :
          !grant.daemon_ids.every((d) => currentGrant.daemon_ids.includes(d)))) return error("forbidden", "Local grant changed");
      return outcome;
    } catch (cause) {
      const detail = cause instanceof Error ? cause.message : "";
      const code = cause instanceof SupervisorOfflineError ? "offline" : /timeout|timed out/i.test(detail) ? "timeout" :
        cause instanceof SupervisorReplyError ? "invalid_argument" : "internal";
      const outcome = error(code, "Supervisor request failed");
      // Only the dispatch call itself can establish no effect from an offline
      // connect or explicit rejection. A failed observation after IPC (or during
      // recovery) must preserve the durable uncertain outcome for reconciliation.
      if (entry && dispatching) {
        entry.outcome = outcome;
        if (cause instanceof SupervisorOfflineError || cause instanceof SupervisorReplyError) entry.pending = false;
        this.save();
      }
      return outcome;
    }
  }
}
