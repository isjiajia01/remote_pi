import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer, type Server, type Socket } from "node:net";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { PerchControl, loadPerchControlConfig } from "./perch_control.js";
import { PERCH_CONTROL_METHODS, controlOperation } from "./perch_control_protocol.js";
import { callSupervisor } from "./client.js";
import type { ControlRequest, CronJobView, DaemonInfo } from "./control_protocol.js";
import type { PerchClientMessage, PerchServerMessage } from "../protocol/perch.js";
import { decodeServer, encodeClient } from "../protocol/codec.js";

const owner = Buffer.alloc(32, 1).toString("base64");
const stranger = Buffer.alloc(32, 2).toString("base64");
const daemon = "1234abcd";
const otherDaemon = "deadbeef";
const wireError = (code: string) => ({ type: "perch_error", error: { code } });
function request(id: string, method = "daemon.start", params: Record<string, unknown> = { id: daemon }, revision?: number): PerchClientMessage {
  return { type: "perch_request", id, version: 1, method, params, ...(revision === undefined ? {} : { expected_revision: revision }) };
}
function fixture(name: string) {
  return JSON.parse(readFileSync(new URL(`../../../.orchestration/contracts/perch-v1/${name}.json`, import.meta.url), "utf8"));
}
function job(id: string, daemon_id = daemon): CronJobView {
  return { id, daemon_id, schedule: "0 * * * *", prompt: "Check inbox", enabled: true,
    skip_if_busy: true, wake: false, catchup: false, created_at: "2026-10-19T00:00:00.000Z" };
}

/** Real isolated JSONL UDS; no Supervisor, child process, keyring or production paths. */
class FakeSupervisor {
  readonly daemons: DaemonInfo[] = [
    { id: daemon, cwd: "/test/a", name: "A", state: "stopped" },
    { id: otherDaemon, cwd: "/test/b", name: "B", state: "stopped" },
  ];
  readonly jobs: CronJobView[] = [job("j_a1"), job("j_b2", otherDaemon)];
  readonly effects: ControlRequest[] = [];
  readonly requests: ControlRequest[] = [];
  readonly sockets = new Set<Socket>();
  server?: Server;
  hangMutation = false;
  dieAfterMutation = false;
  beforeSnapshot?: () => void;
  constructor(readonly path: string) {}
  async start() {
    this.server = createServer((socket) => {
      this.sockets.add(socket);
      socket.once("close", () => this.sockets.delete(socket));
      socket.on("error", () => {});
      let buffer = "";
      socket.on("data", (chunk) => {
        buffer += chunk.toString();
        if (!buffer.includes("\n")) return;
        const req = JSON.parse(buffer.split("\n")[0]) as ControlRequest;
        this.requests.push(req);
        let data: unknown;
        if (req.op === "list") { this.beforeSnapshot?.(); data = { daemons: this.daemons }; }
        else if (req.op === "cron_list") data = { jobs: this.jobs };
        else if (req.op === "cron_log") data = { entries: [{ job_id: req.job_id, daemon_id: daemon, fired: true }] };
        else {
          this.effects.push(req);
          switch (req.op) {
            case "start": case "restart": this.daemons.find((d) => d.id === req.id)!.state = "running";
              data = { id: req.id, state: "running", [req.op === "start" ? "started" : "restarted"]: true }; break;
            case "stop": this.daemons.find((d) => d.id === req.id)!.state = "stopped";
              data = { id: req.id, state: "stopped", stopped: true }; break;
            case "cron_add": { const { op: _, ...fields } = req; const added = { ...job("j_c3"), ...fields }; this.jobs.push(added); data = { job: added }; break; }
            case "cron_remove": this.jobs.splice(this.jobs.findIndex((j) => j.id === req.job_id), 1); data = { removed: true }; break;
            case "cron_enable": this.jobs.find((j) => j.id === req.job_id)!.enabled = req.enabled;
              data = { job_id: req.job_id, enabled: req.enabled, updated: true }; break;
            case "cron_run": data = { job_id: req.job_id, result: "delivered" }; break;
            default: throw new Error(`Unexpected remote operation ${req.op}`);
          }
          if (this.hangMutation) return;
        }
        socket.end(JSON.stringify({ ok: true, data }) + "\n");
        if (this.dieAfterMutation && req.op !== "list" && req.op !== "cron_list") {
          this.server?.close();
          this.server = undefined;
        }
      });
    });
    await new Promise<void>((resolve, reject) => {
      this.server!.once("error", reject);
      this.server!.listen(this.path, resolve);
    });
  }
  async stop() {
    for (const socket of this.sockets) socket.destroy();
    if (this.server) await new Promise<void>((resolve) => this.server!.close(() => resolve()));
    this.server = undefined;
  }
}

let root: string;
let configPath: string;
let journalPath: string;
let fake: FakeSupervisor;
let control: PerchControl;
let paired: boolean;
function config(operations: readonly string[] = PERCH_CONTROL_METHODS, ids = [daemon]) {
  writeFileSync(configPath, JSON.stringify({ enabled: true, owners: { [owner]: { operations, daemon_ids: ids } } }));
}
function fresh() {
  return new PerchControl({ configPath, journalPath, isPaired: async (key) => paired && key === owner,
    supervisor: { sockPath: fake.path, connectTimeoutMs: 100, replyTimeoutMs: 100 } });
}
async function negotiate(c = control) {
  return c.handle(owner, { type: "perch_capabilities_get", id: "cap-control" });
}
beforeEach(async () => {
  root = mkdtempSync(join(tmpdir(), "perch-control-"));
  configPath = join(root, "grants.json");
  journalPath = join(root, "journal.json");
  fake = new FakeSupervisor(join(root, "s.sock"));
  await fake.start();
  paired = true;
  config();
  control = fresh();
});
afterEach(async () => { await fake.stop(); rmSync(root, { recursive: true, force: true }); });

describe("Perch control authorization and validation", () => {
  test("golden capabilities negotiate only local operations and all control messages roundtrip", async () => {
    const f = fixture("control-capabilities");
    expect(await control.handle(owner, f.request)).toEqual(f.response);
    for (const name of ["control-capabilities", "daemon-start", "cron-add", "control-conflict", "control-ambiguous"]) {
      const wire = fixture(name);
      expect(JSON.parse(encodeClient(wire.request))).toEqual(wire.request);
      expect(decodeServer(JSON.stringify(wire.response))).toEqual(wire.response);
    }
    const start = fixture("daemon-start");
    expect(await control.handle(owner, start.request)).toEqual(start.response);
    const conflict = fixture("control-conflict");
    expect(await control.handle(owner, conflict.request)).toEqual(conflict.response);
    const cron = fixture("cron-add");
    expect(await control.handle(owner, cron.request)).toEqual(cron.response);
  });
  test("unauthenticated and revoked owners have no effects, including replay", async () => {
    expect(await control.handle(stranger, request("bad"))).toMatchObject(wireError("unauthorized"));
    await negotiate();
    const msg = request("start");
    await control.handle(owner, msg);
    paired = false;
    expect(await control.handle(owner, msg)).toMatchObject(wireError("unauthorized"));
    expect(await control.handle(owner, request("stop", "daemon.stop"))).toMatchObject(wireError("unauthorized"));
    expect(fake.effects).toHaveLength(1);
  });
  test("absent, malformed, disabled or unknown-field local grants default deny", async () => {
    rmSync(configPath);
    expect(await negotiate()).toMatchObject(wireError("forbidden"));
    for (const contents of ["{", "{}", JSON.stringify({ enabled: false, owners: {} }),
      JSON.stringify({ enabled: true, owners: {}, surprise: true }),
      JSON.stringify({ enabled: true, owners: { [owner]: { operations: ["daemon.start"], daemon_ids: [daemon], shell: true } } }),
      JSON.stringify({ enabled: true, owners: { [owner]: { operations: ["shell.exec"], daemon_ids: [daemon] } } })]) {
      writeFileSync(configPath, contents);
      expect(loadPerchControlConfig(configPath).enabled).toBe(false);
      expect(await control.handle(owner, request("bad"))).toMatchObject(wireError("forbidden"));
    }
    expect(fake.requests).toHaveLength(0);
  });
  test("requires negotiation and grants per operation and daemon, rechecks after snapshot", async () => {
    expect(await control.handle(owner, request("first"))).toMatchObject(wireError("unsupported"));
    config(["daemon.stop", "daemon.start"]);
    await negotiate();
    expect(await control.handle(owner, request("other", "daemon.start", { id: otherDaemon }))).toMatchObject(wireError("forbidden"));
    expect(await control.handle(owner, request("cron", "cron.run", { job_id: "j_a1" }))).toMatchObject(wireError("forbidden"));
    fake.beforeSnapshot = () => { paired = false; };
    expect(await control.handle(owner, request("revoked"))).toMatchObject(wireError("unauthorized"));
    expect(fake.effects).toHaveLength(0);
  });
  test("unknown methods, shell/path forwarding, unbounded prompts and invalid params have no effects", async () => {
    await negotiate();
    for (const method of ["shell.exec", "daemon.register", "daemon.stop_all"]) {
      expect(await control.handle(owner, request(method, method, {}))).toMatchObject(wireError("unsupported"));
    }
    const invalid = [request("path", "daemon.start", { id: daemon, cwd: "/tmp" }),
      request("id", "daemon.stop", { id: "all" }), request("log", "cron.log", { job_id: "j_a1", tail: 101 }),
      request("global-log", "cron.log", {}), request("flag", "cron.set_enabled", { job_id: "j_a1", enabled: "true" }),
      request("prompt", "cron.add", { daemon_id: daemon, schedule: "* * * * *", prompt: "x".repeat(8193) }),
      request("schedule", "cron.add", { daemon_id: daemon, schedule: "* * * * * *", prompt: "x" }),
      { ...request("extra"), command: "echo bad" }, { ...request("revision"), expected_revision: -1 }];
    for (const msg of invalid) expect(await control.handle(owner, msg)).toMatchObject(wireError("invalid_argument"));
    expect(fake.effects).toHaveLength(0);
  });
  test("grants removed during request or replay prevent effects/disclosure", async () => {
    await negotiate();
    fake.beforeSnapshot = () => config([]);
    expect(await control.handle(owner, request("denied"))).toMatchObject(wireError("forbidden"));
    expect(fake.effects).toHaveLength(0);
    fake.beforeSnapshot = undefined;
    config();
    const msg = request("list", "daemon.list", {});
    await control.handle(owner, msg);
    config(PERCH_CONTROL_METHODS, []);
    expect(await control.handle(owner, msg)).toMatchObject(wireError("forbidden"));
  });
});

describe("Perch durable replay, serialization and revisions", () => {
  test("concurrent replays and process restart return identical stored outcome, changed digest conflicts", async () => {
    await negotiate();
    const msg = request("once", "daemon.start", { id: daemon }, 0);
    const results = await Promise.all(Array.from({ length: 8 }, () => control.handle(owner, msg)));
    for (const result of results) expect(result).toEqual(results[0]);
    expect(fake.effects).toHaveLength(1);
    const ipcCount = fake.requests.length;
    control = fresh(); await negotiate();
    expect(await control.handle(owner, msg)).toEqual(results[0]);
    expect(fake.requests).toHaveLength(ipcCount);
    expect(await control.handle(owner, { ...msg, method: "daemon.stop" })).toMatchObject(wireError("conflict"));
    expect(fake.effects).toHaveLength(1);
    config(["daemon.stop"]);
    expect(await control.handle(owner, msg)).toMatchObject(wireError("forbidden"));
  });
  test("serializes mutations and checks revision against current IPC state", async () => {
    await negotiate();
    const results = await Promise.all([
      control.handle(owner, request("a", "daemon.start", { id: daemon }, 0)),
      control.handle(owner, request("b", "daemon.stop", { id: daemon }, 0)),
    ]);
    expect(results[0]).toMatchObject({ type: "perch_result" });
    expect(results[1]).toMatchObject(wireError("conflict"));
    expect(fake.effects).toHaveLength(1);
    const list = await control.handle(owner, request("list", "daemon.list", {}));
    if (list.type !== "perch_result" || list.result.scope !== "supervisor") throw new Error("missing list");
    fake.daemons[0].state = "stopped"; // Local CLI/scheduler changes invalidate stale remote revisions.
    expect(await control.handle(owner, request("stale", "daemon.start", { id: daemon }, list.result.revision)))
      .toMatchObject(wireError("conflict"));
    expect(fake.effects).toHaveLength(1);
  });
  test("cron job grants resolve daemon ID; scoped lists/logs exclude unrelated daemon", async () => {
    await negotiate();
    expect(await control.handle(owner, request("bad-job", "cron.run", { job_id: "j_b2" }))).toMatchObject(wireError("forbidden"));
    expect(await control.handle(owner, request("jobs", "cron.list", {})))
      .toMatchObject({ result: { data: { jobs: [job("j_a1")] } } });
    expect(await control.handle(owner, request("daemons", "daemon.list", {})))
      .toMatchObject({ result: { data: { daemons: [fake.daemons[0]] } } });
    expect(await control.handle(owner, request("log", "cron.log", { job_id: "j_a1", tail: 3 })))
      .toMatchObject({ type: "perch_result" });
    expect(fake.requests.at(-1)).toEqual({ op: "cron_log", job_id: "j_a1", tail: 3 });
    expect(fake.effects).toHaveLength(0);
  });
  test("every allowed mutation maps to existing IPC; remove replay survives missing job", async () => {
    await negotiate();
    for (const msg of [request("start"), request("stop", "daemon.stop"), request("restart", "daemon.restart"),
      request("add", "cron.add", { daemon_id: daemon, schedule: "0 * * * *", prompt: "Check inbox" }),
      request("enable", "cron.set_enabled", { job_id: "j_a1", enabled: false }),
      request("run", "cron.run", { job_id: "j_a1" })]) {
      expect(await control.handle(owner, msg)).toMatchObject({ type: "perch_result" });
    }
    const remove = request("remove", "cron.remove", { job_id: "j_a1" });
    const outcome = await control.handle(owner, remove);
    control = fresh(); await negotiate();
    expect(await control.handle(owner, remove)).toEqual(outcome);
    expect(fake.effects.map((e) => e.op)).toEqual(["start", "stop", "restart", "cron_add", "cron_enable", "cron_run", "cron_remove"]);
    config(PERCH_CONTROL_METHODS, []);
    expect(await control.handle(owner, remove)).toMatchObject(wireError("forbidden"));
  });
  test("timeout after cron IPC reconciles on restart and never fires again; no blind daemon restart", async () => {
    await negotiate();
    fake.hangMutation = true;
    const run = request("uncertain", "cron.run", { job_id: "j_a1" });
    expect(await control.handle(owner, run)).toMatchObject(wireError("timeout"));
    expect(fake.effects).toHaveLength(1);
    const journal = JSON.parse(readFileSync(journalPath, "utf8"));
    expect(Object.values(journal.entries)).toEqual([expect.objectContaining({ pending: true })]);
    fake.hangMutation = false;
    control = fresh(); await negotiate();
    const prior = fake.requests.length;
    expect(await control.handle(owner, run)).toMatchObject(wireError("timeout"));
    expect(fake.requests.slice(prior).map((r) => r.op)).toEqual(["list", "cron_list"]);
    expect(fake.effects).toHaveLength(1);
    // Simulate process death after successful IPC but before outcome persistence.
    await control.handle(owner, request("restart", "daemon.restart"));
    const crashed = JSON.parse(readFileSync(journalPath, "utf8"));
    const last = Object.values(crashed.entries).at(-1) as { pending: boolean; outcome: unknown };
    last.pending = true;
    last.outcome = { type: "perch_error", id: "restart", version: 1, error: { code: "conflict", message: "Previous IPC outcome uncertain; state reconciled, inspect fresh lists before a new request" } };
    writeFileSync(journalPath, JSON.stringify(crashed));
    control = fresh(); await negotiate();
    const ambiguous = fixture("control-ambiguous");
    expect(await control.handle(owner, ambiguous.request)).toEqual(ambiguous.response);
    expect(fake.effects).toHaveLength(2);
  });
  test.each(["cron.run", "cron.add"])("supervisor death after %s preserves uncertainty across failed recovery", async (method) => {
    await negotiate();
    fake.dieAfterMutation = true;
    const msg = request("death", method, method === "cron.run" ? { job_id: "j_a1" } :
      { daemon_id: daemon, schedule: "0 * * * *", prompt: "Check inbox" });
    expect(await control.handle(owner, msg)).toMatchObject(wireError("offline"));
    expect(fake.effects).toHaveLength(1);
    const pendingEntry = () => Object.values(JSON.parse(readFileSync(journalPath, "utf8")).entries)[0];
    expect(pendingEntry()).toMatchObject({ pending: true, outcome: { error: { code: "conflict" } } });
    control = fresh(); await negotiate();
    expect(await control.handle(owner, msg)).toMatchObject(wireError("offline"));
    expect(pendingEntry()).toMatchObject({ pending: true, outcome: { error: { code: "conflict" } } });
    fake.dieAfterMutation = false;
    // Test-only listener restart preserves fake state to represent supervisor recovery.
    rmSync(fake.path, { force: true });
    await fake.start();
    expect(await control.handle(owner, msg)).toMatchObject(wireError("conflict"));
    expect(pendingEntry()).toMatchObject({ pending: false, outcome: { error: { code: "conflict" } } });
    expect(fake.effects).toHaveLength(1);
  });
  test("stopping every child leaves endpoint able to restart one", async () => {
    config(PERCH_CONTROL_METHODS, [daemon, otherDaemon]); await negotiate();
    for (const id of [daemon, otherDaemon]) {
      await control.handle(owner, request(`start-${id}`, "daemon.start", { id }));
      await control.handle(owner, request(`stop-${id}`, "daemon.stop", { id }));
    }
    expect(fake.daemons.every((d) => d.state === "stopped")).toBe(true);
    expect(await control.handle(owner, request("recover"))).toMatchObject({ type: "perch_result" });
    expect(fake.daemons[0].state).toBe("running");
  });
  test("offline errors are bounded; corrupt journal refuses startup", async () => {
    await negotiate(); await fake.stop();
    expect(await control.handle(owner, request("offline"))).toMatchObject(wireError("offline"));
    writeFileSync(journalPath, "{}");
    expect(() => fresh()).toThrow("Invalid Perch control journal");
  });
  test("IPC timeout closes sockets instead of hanging", async () => {
    fake.hangMutation = true;
    await expect(callSupervisor({ op: "start", id: daemon }, { sockPath: fake.path, replyTimeoutMs: 20 })).rejects.toThrow("timeout");
  });
});

describe("control param allowlist", () => {
  test("never forwards arbitrary IPC operations or fields", () => {
    for (const method of ["register", "send", "start_all", "cron_update", "exec"]) {
      expect(controlOperation(method, { cwd: "/tmp", text: "x" })).toBeUndefined();
    }
  });
});
